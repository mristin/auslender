"""Shrink the textures of a glTF binary (.glb), e.g. of a generated model.

python shrink_textures.py <in.glb> <out.glb> [max size, default 1024]

Every embedded image larger than the max size is scaled down to it (keeping
its aspect) and stored again as PNG; the rest of the file stays as it is. The
game shows the heroes small (the camera panel, the arms in the first person),
so textures of 4096 pixels only cost space.
"""

import io
import json
import struct
import sys

from PIL import Image


def main() -> int:
    source, target = sys.argv[1], sys.argv[2]
    largest = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
    data = open(source, "rb").read()
    magic, version, _ = struct.unpack("<4sII", data[:12])
    assert magic == b"glTF" and version == 2, "Expected a glTF 2.0 binary."
    json_length, json_type = struct.unpack("<I4s", data[12:20])
    assert json_type == b"JSON"
    gltf = json.loads(data[20 : 20 + json_length])
    offset = 20 + json_length
    bin_length, bin_type = struct.unpack("<I4s", data[offset : offset + 8])
    assert bin_type == b"BIN\x00"
    binary = data[offset + 8 : offset + 8 + bin_length]

    views = gltf["bufferViews"]
    replaced = {}
    for image in gltf.get("images", []):
        if "bufferView" not in image:
            continue
        view = views[image["bufferView"]]
        start = view.get("byteOffset", 0)
        picture = Image.open(io.BytesIO(binary[start : start + view["byteLength"]]))
        if max(picture.size) > largest:
            picture.thumbnail((largest, largest), Image.LANCZOS)
        out = io.BytesIO()
        picture.save(out, format="PNG", optimize=True)
        replaced[image["bufferView"]] = out.getvalue()
        image["mimeType"] = "image/png"
        print(f"image {image['bufferView']}: {view['byteLength']} -> {len(out.getvalue())} bytes, {picture.size}")

    # NOTE: lay the buffer views out anew, each aligned to 4 bytes.
    chunks = []
    position = 0
    for index, view in enumerate(views):
        start = view.get("byteOffset", 0)
        content = replaced.get(index, binary[start : start + view["byteLength"]])
        padding = (-position) % 4
        chunks.append(b"\x00" * padding)
        position += padding
        view["byteOffset"] = position
        view["byteLength"] = len(content)
        chunks.append(content)
        position += len(content)
    new_binary = b"".join(chunks)
    new_binary += b"\x00" * ((-len(new_binary)) % 4)
    gltf["buffers"][0]["byteLength"] = len(new_binary)

    text = json.dumps(gltf, separators=(",", ":")).encode()
    text += b" " * ((-len(text)) % 4)
    total = 12 + 8 + len(text) + 8 + len(new_binary)
    with open(target, "wb") as out:
        out.write(struct.pack("<4sII", b"glTF", 2, total))
        out.write(struct.pack("<I4s", len(text), b"JSON") + text)
        out.write(struct.pack("<I4s", len(new_binary), b"BIN\x00") + new_binary)
    print(f"Wrote {target}: {len(data)} -> {total} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())

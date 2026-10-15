"""Check generated metadata against the archive before publishing it."""
import base64
import pathlib
import sys
import xml.etree.ElementTree as ET

feed, archive, version, architecture = sys.argv[1:]
sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
items = ET.parse(feed).findall('./channel/item')
item = next(i for i in items if i.findtext(sparkle + 'version') == version)
# Sparkle emits an explicit arm64 requirement, but omits it for Intel archives.
# Separate feed routing and the packager's Mach-O check enforce Intel selection.
hardware = item.findtext(sparkle + 'hardwareRequirements')
assert hardware == 'arm64' if architecture == 'arm64' else hardware in (None, 'x86_64')
assert item.findtext(sparkle + 'minimumSystemVersion') == '14.0'
enclosure = item.find('enclosure')
assert enclosure is not None
assert enclosure.attrib['url'] == f'https://github.com/lyova24/keepy/releases/download/v{version}/{pathlib.Path(archive).name}'
assert int(enclosure.attrib['length']) == pathlib.Path(archive).stat().st_size
assert len(base64.b64decode(enclosure.attrib[sparkle + 'edSignature'], validate=True)) == 64
assert b'sparkle-signatures:' in pathlib.Path(feed).read_bytes()
print(f'Update metadata verified: {version}, {architecture}.')

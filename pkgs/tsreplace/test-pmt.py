import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

source = (Path(sys.argv[1]) / 'app/tsreplace.cpp').read_text()
start = source.index('RGY_ERR TSReplace::writeReplacedPMT(')
end = source.index('void TSReplace::pushPESPTS(', start)
branch = source[source.index('case RGYTSPacketType::PMT:'):source.index('case RGYTSPacketType::PCR:')]
dispatch = re.search(r'(if \(tspkt->header.PayloadStartFlag\) \{\s+writeReplacedPMT\(ret\);\s+\}|writeReplacedPMT\(ret\);)\s+break;', branch).group(1)
template = Path(sys.argv[2]).read_text().replace('@dispatch@', dispatch)
if template.count('@implementation@') != 1:
    raise RuntimeError('Expected one implementation placeholder')
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'test.cpp').write_text(template.replace('@implementation@', source[start:end]))
    compiler = shlex.split(os.environ.get('CXX', 'c++'))
    subprocess.run([*compiler, '-std=c++17', '-O2', str(path / 'test.cpp'), '-o', str(path / 'test')], check=True)
    subprocess.run([str(path / 'test')], check=True)

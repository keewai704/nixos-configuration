import sys
from pathlib import Path

path = Path(sys.argv[1]) / 'server/app/models/Channel.py'
text = path.read_text()
old = '                services = EDCBUtil.parseChSet5(EDCBUtil.convertBytesToString(chset5_txt))'
if text.count(old) != 1:
    raise RuntimeError('EDCB channel import changed upstream')
new = old + '''
                services = [service for service in services
                            if service['epg_cap_flag'] or service['search_flag']]'''
path.write_text(text.replace(old, new))

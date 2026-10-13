#!/usr/bin/env python3
import array
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys


def editable_files(command, paths, bottles_root):
    external = [
        Path(path).resolve()
        for path in paths
        if Path(path).is_file()
        and not Path(path).resolve().is_relative_to(bottles_root)
    ]
    if not external:
        return paths
    subprocess.run(command + ['@/usr/bin/true'], check=True, stdout=subprocess.DEVNULL)
    state = json.loads(subprocess.check_output(
        ['cpak', 'inspect', 'github.com/bottlesdevs/bottles'], text=True
    ))
    if isinstance(state, list):
        state = next(item for item in state if item['instance'] == '' and item['container'] == 'running')
    data_home = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    grant_socket = data_home / 'cpak/store/states' / state['container_id'] / 'grant.sock'
    mounted = {}
    for parent in dict.fromkeys(path.parent for path in external):
        origin = 'github.com/bottlesdevs/bottles'
        source = str(parent)
        scope = '\0'.join([origin, source, source, 'directory', 'read-write'])
        grant_id = hashlib.sha256(scope.encode()).hexdigest()
        target = f'/run/cpak/grants/{grant_id}/{parent.name}'
        grant = dict(id=grant_id, origin=origin, selection=source, source=source,
                     target=target, mount_target=target, kind='directory',
                     access='read-write', lifetime='session')
        descriptor = os.open(
            parent, os.O_PATH | os.O_DIRECTORY | os.O_CLOEXEC | os.O_NOFOLLOW
        )
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET) as connection:
                connection.settimeout(15)
                connection.connect(str(grant_socket))
                connection.sendmsg(
                    [json.dumps({'grant': grant}).encode()],
                    [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array('i', [descriptor]))],
                )
                response = json.loads(connection.recv(65536))
                if response.get('error') or response.get('target') != target:
                    raise RuntimeError(response.get('error', 'Invalid cpak file grant target'))
        finally:
            os.close(descriptor)
        mounted[parent] = target
    rewritten = {str(path): mounted[path.parent] + '/' + path.name for path in external}
    return [rewritten.get(str(Path(path).resolve()), path) for path in paths]


if os.environ.get('HYPRLAND_INSTANCE_SIGNATURE'):
    rule = '''if not bottles_office_window_rules_v2 then
        hl.window_rule({
            match = { class = "^(excel|winword|powerpnt)[.]exe$" },
            opacity = "1.0 override 1.0 override 1.0 override",
            rounding = 0
        })
        hl.window_rule({
            match = {
                class = "^(excel|winword|powerpnt)[.]exe$",
                title = "^(Microsoft (Word|Excel|PowerPoint)|ジャンプ|名前を付けて保存|ファイルを開く|セルの書式設定|(Word|Excel|PowerPoint) のオプション)$"
            },
            float = true,
            center = true
        })
        bottles_office_window_rules_v2 = true
    end'''
    subprocess.run(['hyprctl', 'eval', rule], stdout=subprocess.DEVNULL, check=False)

root = Path.home() / '.local/share/bottles'
runtime = root / 'compat/nvidia-runtime'
runtime.mkdir(parents=True, exist_ok=True)
with (runtime / '.update-lock').open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    source = Path('/run/opengl-driver/lib/libGLX_nvidia.so.0').resolve(strict=True).parent
    stamp = runtime / '.driver-source'
    if not stamp.exists() or stamp.read_text() != str(source):
        prefixes = ('libGLX_nvidia.', 'libEGL_nvidia.', 'libnvidia-glcore.', 'libnvidia-glsi.', 'libnvidia-gpucomp.', 'libnvidia-glvkspirv.', 'libnvidia-eglcore.', 'libnvidia-allocator.', 'libnvidia-tls.', 'libnvidia-rtcore.', 'libnvidia-present.', 'libnvidia-ml.')
        for library in source.iterdir():
            if not library.name.startswith(prefixes):
                continue
            real = library.resolve(strict=True)
            destination = runtime / real.name
            if not destination.exists() or destination.stat().st_size != real.stat().st_size:
                temporary = runtime / (real.name + '.new')
                shutil.copy2(real, temporary)
                temporary.replace(destination)
            if library.name != real.name:
                temporary = runtime / (library.name + '.new')
                temporary.unlink(missing_ok=True)
                temporary.symlink_to(real.name)
                temporary.replace(runtime / library.name)
        for name, relative, library in [('nvidia_icd.json', 'vulkan/icd.d/nvidia_icd.json', 'libGLX_nvidia.so.0'), ('10_nvidia.json', 'glvnd/egl_vendor.d/10_nvidia.json', 'libEGL_nvidia.so.0')]:
            data = json.loads((source.parent / 'share' / relative).read_text())
            data['ICD']['library_path'] = str(runtime / library)
            temporary = runtime / (name + '.new')
            temporary.write_text(json.dumps(data, indent=2) + '\n')
            temporary.replace(runtime / name)
        stamp.write_text(str(source))
command = ['cpak', 'run', '--branch', 'main', 'github.com/bottlesdevs/bottles']
environment = ['GDK_BACKEND=wayland', 'GSK_RENDERER=cairo', '__GLX_VENDOR_LIBRARY_NAME=mesa', 'LD_LIBRARY_PATH=' + str(runtime)]
arguments = sys.argv[1:]
if arguments[:1] == ['--office']:
    programs = {'word': '813c432c-349a-4eee-b110-41de36d3b186', 'excel': 'e6aefe8b-9347-47f2-b61f-40dedc059d98', 'powerpoint': 'e7704983-004d-45d5-a0d5-d8685f120495'}
    if len(arguments) < 2 or arguments[1] not in programs:
        sys.exit('Usage: bottles-development --office {word,excel,powerpoint} [files...]')
    application = programs[arguments[1]]
    office = """import os, sys
files = ['Z:' + path.replace('/', '\\\\') if path.startswith('/') else path for path in sys.argv[2:]]
os.execv('/usr/bin/bottles-cli', ['bottles-cli', 'run', '-b', 'Microsoft 365', '--program-id', sys.argv[1], *files])
"""
    prefix = environment + ['/usr/bin/python3', '-c', office, application]
    files = [str(Path(path).absolute()) if Path(path).exists() else path for path in arguments[2:]]
    files = editable_files(command, files, root)
else:
    prefix = environment + ['/usr/bin/bottles']
    files = arguments
command += ['--desktop-launch', '--desktop-file-span', f'{len(prefix)},0', '@/usr/bin/env', '--'] + prefix + files
os.execvp(command[0], command)

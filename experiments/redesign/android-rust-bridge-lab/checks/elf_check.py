"""Read actual ELF structures; APK/link inspection is not Android runtime evidence."""
from pathlib import Path
import struct

ABIS = {'arm64-v8a': 183, 'x86_64': 62}
ALLOWED_NEEDED = {'libc.so', 'libdl.so', 'libm.so', 'liblog.so', 'libandroid.so'}


class ElfInvalid(ValueError):
    pass


def inspect(raw, abi, rust=True):
    def reject(condition, code):
        if condition:
            raise ElfInvalid(code)
    def unpack(fmt, offset):
        try:
            return struct.unpack_from(fmt, raw, offset)
        except (struct.error, OverflowError):
            raise ElfInvalid('elf_bounds') from None
    def blob(offset, size):
        reject(offset < 0 or size < 0 or offset + size > len(raw), 'elf_bounds')
        return raw[offset:offset + size]
    def text(table, offset):
        reject(offset < 0 or offset >= len(table), 'elf_string_bounds')
        end = table.find(b'\0', offset)
        reject(end < 0, 'elf_string_bounds')
        try:
            return table[offset:end].decode('ascii')
        except UnicodeError:
            raise ElfInvalid('elf_string') from None
    reject(abi not in ABIS or len(raw) < 64 or raw[:7] != b'\x7fELF\x02\x01\x01', 'elf_header')
    header = unpack('<HHIQQQIHHHHHH', 16)
    kind, machine, version, entry, phoff, shoff, flags, ehsize, phsize, phnum, shsize, shnum, shstrndx = header
    reject(kind != 3 or machine != ABIS[abi] or version != 1 or ehsize != 64 or phsize != 56 or phnum == 0 or phnum > 1024, 'elf_target')
    programs = [unpack('<IIQQQQQQ', phoff + n * phsize) for n in range(phnum)]
    loads = [p for p in programs if p[0] == 1]
    reject(not loads, 'elf_load_missing')
    for p in loads:
        ptype, pflags, offset, vaddr, paddr, filesz, memsz, align = p
        blob(offset, filesz)
        reject(filesz > memsz or align < 0x4000 or align & (align - 1) != 0 or offset % align != vaddr % align, 'elf_load_alignment')
    relro = [p for p in programs if p[0] == 0x6474e552]
    reject(len(relro) != 1 or relro[0][6] == 0, 'elf_relro')
    region = relro[0]
    start, end = region[3], region[3] + region[6]
    reject(end > 1 << 64 or region[5] > region[6], 'elf_relro_mapping')
    blob(region[2], region[5])
    # Linkers may round p_memsz to the final mapped 16KB page. The region
    # must start in real LOAD memory; only its end may occupy that page tail.
    covering = [p for p in loads
                if p[3] <= start < p[3] + p[6]
                and end <= ((p[3] + p[6] + 0x3fff) & ~0x3fff)
                and region[2] == p[2] + start - p[3]
                and region[2] + region[5] <= p[2] + p[5]]
    reject(len(covering) != 1, 'elf_relro_mapping')
    stack = [p for p in programs if p[0] == 0x6474e551]
    reject(len(stack) != 1 or stack[0][1] & 1 != 0, 'elf_executable_stack')
    dynamics = [p for p in programs if p[0] == 2]
    reject(len(dynamics) != 1 or dynamics[0][5] % 16 != 0, 'elf_dynamic')
    entries = []
    for position in range(dynamics[0][2], dynamics[0][2] + dynamics[0][5], 16):
        tag, value = unpack('<qQ', position)
        if tag == 0:
            break
        entries.append((tag, value))
    def singleton(tag):
        matches = [value for key, value in entries if key == tag]
        reject(len(matches) != 1, 'elf_dynamic_tag')
        return matches[0]
    strings_vaddr, strings_size = singleton(5), singleton(10)
    matching = [p for p in loads if p[3] <= strings_vaddr and strings_vaddr + strings_size <= p[3] + p[5]]
    reject(len(matching) != 1, 'elf_string_mapping')
    strings = blob(matching[0][2] + strings_vaddr - matching[0][3], strings_size)
    needed = [text(strings, value) for tag, value in entries if tag == 1]
    reject(not needed or len(needed) != len(set(needed)) or not set(needed) <= ALLOWED_NEEDED or 'libc.so' not in needed, 'elf_needed')
    reject(b'GLIBC_' in raw or any(p[0] == 3 for p in programs), 'elf_desktop_linkage')
    bind_now = any((tag == 24) or (tag == 30 and value & 8) or (tag == 0x6ffffffb and value & 1) for tag, value in entries)
    reject(not bind_now, 'elf_bind_now')
    # NDK crt .note.android.ident: first descriptor word is target API, not runtime.
    android_api = []
    for p in programs:
        if p[0] != 4:
            continue
        position, end = p[2], p[2] + p[5]
        blob(position, p[5])
        while position + 12 <= end:
            namesz, descsz, note_type = unpack('<III', position); position += 12
            name = blob(position, namesz); position += (namesz + 3) & ~3
            desc = blob(position, descsz); position += (descsz + 3) & ~3
            reject(position > end, 'elf_note_bounds')
            if name.rstrip(b'\0') == b'Android' and note_type == 1:
                reject(descsz < 4, 'elf_android_note')
                android_api.append(struct.unpack_from('<I', desc)[0])
    reject((len(android_api) != 1 or android_api[0] != 26) if rust else (len(android_api) > 1 or bool(android_api) and not 1 <= android_api[0] <= 26), 'elf_android_api')
    reject(shsize != 64 or shnum == 0 or shnum > 8192, 'elf_sections')
    sections = [unpack('<IIQQQQIIQQ', shoff + n * shsize) for n in range(shnum)]
    symbols = []
    for section in sections:
        if section[1] != 11:
            continue
        reject(section[9] != 24 or section[5] % 24 != 0 or section[6] >= shnum, 'elf_dynsym')
        strings_section = sections[section[6]]
        names = blob(strings_section[4], strings_section[5])
        for position in range(section[4], section[4] + section[5], 24):
            name, info, other, defined, value, size = unpack('<IBBHQQ', position)
            if defined != 0 and info >> 4 in (1, 2) and other & 3 == 0:
                symbols.append(text(names, name))
    if rust:
        prefix = 'uniffi_muyon_android_contract_bridge_'
        required = {prefix + 'fn_func_bridge_info', prefix + 'fn_func_validate_bundled_contract',
                    prefix + 'checksum_func_bridge_info', prefix + 'checksum_func_validate_bundled_contract'}
        reject(not required <= set(symbols), 'elf_bridge_exports')
        reject(any('ffi_test_panic_probe' in symbol for symbol in symbols), 'elf_probe_in_shipping')
    else:
        reject(not any(name.startswith('Java_com_sun_jna_Native_') for name in symbols), 'elf_jna_exports')
    return dict(abi=abi, elf_class=64, machine=machine, declared_android_api=android_api[0] if android_api else None,
                needed=needed, load_alignments=[p[7] for p in loads], relro=True, bind_now=True,
                stack_executable=False, exported_symbols=sorted(set(symbols)))

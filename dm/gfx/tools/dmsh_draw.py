"""Draw parameters which must follow GPU-written indirect arguments."""
import re


def native_base_instance(src):
    """Read NVN c0 + 0x644 from Metal's vertex base_instance input.

    The CPU cannot populate this word for an indirect draw: its arguments may
    have been written by compute earlier in the same submission. Maxwell's
    instance ID excludes the base; SPIRV-Cross already subtracts base_instance
    from Metal's instance_id. GLSLC's subsequent c0 load must add the real base
    back, rather than the zero in the replay's CPU-built driver segment.
    """
    load = r'\(\*spvDescriptorSet0\.vp_c0\)\._m0\[100\](?:\.y|\[1\])'
    if not re.search(load, src):
        return src

    # The translator represents uniform words as float4 and bitcasts integer
    # reads. Keep the bits of the unsigned native input, including bit 31.
    src = re.sub(load, 'as_type<float>(gl_BaseInstance)', src)
    entries = 0

    def entry(match):
        nonlocal entries
        entries += 1
        signature = match[0]
        existing = re.search(r'\b(\w+)\s*\[\[base_instance\]\]', signature)
        if existing:
            if existing[1] != 'gl_BaseInstance':
                raise ValueError('unexpected Metal base_instance parameter name')
            return signature
        return signature[:-3] + ', uint gl_BaseInstance [[base_instance]])\n{'

    src = re.sub(r'^vertex [^{]+\)\n\{', entry, src, flags=re.M)
    if not entries:
        raise ValueError('NVN base instance read without a Metal vertex entry point')
    return src

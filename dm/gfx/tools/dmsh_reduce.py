"""Offline reduction-sampler fallback for proven 2D integer-LOD clamp bindings.

The profile identifies the shader and slot; replay checks the sampler contract.
Native minimum/maximum samplers require Apple10, so earlier GPUs use texel reads.
"""
import re

MSL = r'''
// Normalized coordinates, linear texel filtering, nearest integer mip, clamp to edge.
// Maxwell interpolation weights have eight fractional bits. A zero-weight texel
// must not contribute, including a fraction rounded all the way up to one.
static inline float4 dm_minmax_2d_integer_clamp(texture2d<float> t, float2 uv, float lod, uint mode)
{
    uint l = uint(clamp(lod, 0.0f, float(t.get_num_mip_levels() - 1)));
    int2 size = int2(t.get_width(l), t.get_height(l));
    float2 p = clamp(uv, float2(0.0f), float2(1.0f)) * float2(size) - 0.5f;
    int2 a = int2(floor(p));
    int2 q = int2(floor((p - float2(a)) * 256.0f + 0.5f));
    if (q.x == 256) { a.x++; q.x = 0; }
    if (q.y == 256) { a.y++; q.y = 0; }
    float4 r = t.read(uint2(clamp(a, int2(0), size - 1)), l);
    if (q.x) {
        float4 v = t.read(uint2(clamp(a + int2(1, 0), int2(0), size - 1)), l);
        r = mode == 1 ? fmin(r, v) : fmax(r, v);
    }
    if (q.y) {
        float4 v = t.read(uint2(clamp(a + int2(0, 1), int2(0), size - 1)), l);
        r = mode == 1 ? fmin(r, v) : fmax(r, v);
        if (q.x) {
            v = t.read(uint2(clamp(a + int2(1, 1), int2(0), size - 1)), l);
            r = mode == 1 ? fmin(r, v) : fmax(r, v);
        }
    }
    return r;
}
'''


def _args(src, start):
    out, depth, at = [], 0, start
    for i in range(start, len(src)):
        c = src[i]
        if c == '(':
            depth += 1
        elif c == ')':
            if not depth:
                return out + [src[at:i].strip()], i + 1
            depth -= 1
        elif c == ',' and not depth:
            out.append(src[at:i].strip()); at = i + 1
    raise ValueError('unterminated reduction sample')


def apply(src, bindings, spec):
    """spec = {NVN texture slot: 1 minimum / 2 maximum}. Unsupported forms fail."""
    if not spec:
        return src
    for slot, mode in spec.items():
        if mode not in (1, 2):
            raise ValueError('reduction mode must be minimum or maximum')
        tex = [b for b in bindings if b.get('kind') == 'tex' and b.get('reg') == slot]
        if len(tex) != 1 or tex[0]['msl_type'] != 'texture2d<float>':
            raise ValueError(f'reduction slot {slot}: expected one float texture2d binding')
        name = tex[0]['msl_name']; prefix = 'spvDescriptorSet0.' + name
        if re.search(re.escape(prefix) + r'\.(?:sample_compare|gather|gather_compare)\(', src):
            raise ValueError(f'reduction slot {slot}: comparison and gather samples are not supported')
        edits = []
        for m in re.finditer(re.escape(prefix) + r'\.sample\(', src):
            args, end = _args(src, m.end())
            lod = re.fullmatch(r'level\((.*)\)', args[2], re.S) if len(args) == 3 else None
            if not lod or args[0] != prefix + 'Smplr':
                raise ValueError(f'reduction slot {slot}: expected an explicit-LOD sample without offsets')
            edits.append((m.start(), end, f'dm_minmax_2d_integer_clamp({prefix}, {args[1]}, {lod[1]}, {mode}u)'))
        if not edits:
            raise ValueError(f'reduction slot {slot}: no explicit-LOD samples')
        for a, b, text in reversed(edits):
            src = src[:a] + text + src[b:]
        samps = [b for b in bindings if b.get('msl_name') == name + 'Smplr']
        if len(samps) != 1:
            raise ValueError(f'reduction slot {slot}: missing sampler binding')
        samps[0]['reduce'] = mode
    return src.replace('using namespace metal;', 'using namespace metal;\n' + MSL, 1)

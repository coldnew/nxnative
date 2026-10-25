"""NVN base instance must follow direct and GPU-written indirect draw arguments."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import dmsh_draw


SOURCE = r'''#include <metal_stdlib>
using namespace metal;
struct D { float4 _m0[101]; };
struct B { constant D* vp_c0; };
vertex void main0(uint gl_InstanceIndex [[instance_id]], uint gl_BaseInstance [[base_instance]], constant D& driver [[buffer(0)]], device atomic_uint* result [[buffer(2)]])
{
    B spvDescriptorSet0 = { &driver };
    uint relative = gl_InstanceIndex - gl_BaseInstance;
    uint index = relative + as_type<uint>((*spvDescriptorSet0.vp_c0)._m0[100].y);
    atomic_store_explicit(result + relative, index, memory_order_relaxed);
}
kernel void fill(device uint* args [[buffer(0)]], constant uint2& config [[buffer(1)]])
{
    args[0] = 3; args[1] = 2; args[2] = 0;
    args[3] = config.y ? 0 : config.x; args[4] = config.x;
}
'''


class DrawParameters(unittest.TestCase):
    def test_no_driver_load_is_unchanged(self):
        self.assertEqual(dmsh_draw.native_base_instance('vertex unchanged'), 'vertex unchanged')

    def test_existing_and_added_builtin(self):
        fixed = dmsh_draw.native_base_instance(SOURCE)
        self.assertEqual(fixed.count('[[base_instance]]'), 1)
        self.assertNotIn('vp_c0)._m0[100].y', fixed)
        missing = SOURCE.replace(', uint gl_BaseInstance [[base_instance]]', '')
        self.assertEqual(dmsh_draw.native_base_instance(missing).count('[[base_instance]]'), 1)
        self.assertEqual(dmsh_draw.native_base_instance(fixed), fixed)

    def test_other_driver_words_are_preserved(self):
        source = SOURCE.replace('uint index =', 'float other = (*spvDescriptorSet0.vp_c0)._m0[100].x; uint index =')
        self.assertIn('vp_c0)._m0[100].x', dmsh_draw.native_base_instance(source))

    def test_gpu_draws(self):
        with tempfile.TemporaryDirectory(prefix='draw_parameters_') as directory:
            root = Path(directory)
            host = root / 'test'
            subprocess.run(['clang', '-fobjc-arc', str(Path(__file__).with_name('t_draw_parameters.m')),
                            '-framework', 'Foundation', '-framework', 'Metal', '-o', str(host)], check=True, capture_output=True)
            missing = SOURCE.replace(', uint gl_BaseInstance [[base_instance]]', '')
            libraries = []
            for name, source in [('old', SOURCE), ('native', dmsh_draw.native_base_instance(SOURCE)),
                                 ('added', dmsh_draw.native_base_instance(missing))]:
                path = root / f'{name}.metal'
                path.write_text(source)
                for sdk in ('macosx', 'iphoneos'):
                    result = subprocess.run(['xcrun', '-sdk', sdk, 'metal', '-c', str(path), '-o', str(root / f'{name}.{sdk}.air')], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                library = root / f'{name}.metallib'
                subprocess.run(['xcrun', '-sdk', 'macosx', 'metallib', str(root / f'{name}.macosx.air'), '-o', str(library)], check=True, capture_output=True)
                libraries.append((name, library))
            for name, library in libraries:
                result = subprocess.run([str(host), str(library)], capture_output=True, text=True)
                if result.returncode == 77:
                    self.skipTest('Metal device unavailable; all shader fixtures compiled for macOS and iOS')
                self.assertEqual(result.returncode, 0, result.stderr)
                rows = [list(map(int, line.split())) for line in result.stdout.splitlines()]
                self.assertEqual(len(rows), 12)
                for base, indirect, first, second in rows:
                    expected = 0 if name == 'old' else base
                    self.assertEqual((first, second), (expected, expected + 1), (name, indirect, result.stdout))


if __name__ == '__main__':
    unittest.main()

import copy
import pathlib
import subprocess
import sys
import tempfile
import unittest

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'tools'))
import dmsh_reduce


class ReductionTests(unittest.TestCase):
    def bindings(self):
        return [{'kind': 'tex', 'reg': 17, 'msl_name': 't', 'msl_type': 'texture2d<float>'},
                {'kind': 'samp_tex', 'reg': 17, 'msl_name': 'tSmplr', 'msl_type': 'sampler'}]

    def test_explicit_sample_preserves_direct_reads(self):
        src = 'using namespace metal;\nfloat4 a=spvDescriptorSet0.t.sample(spvDescriptorSet0.tSmplr, select(v,float2(0),isnan(v)),level(float(i)));\nfloat4 b=spvDescriptorSet0.t.read(uint2(1),0);'
        bindings = self.bindings()
        out = dmsh_reduce.apply(src, bindings, {17: 1})
        self.assertIn('dm_minmax_2d_integer_clamp(spvDescriptorSet0.t, select(v,float2(0),isnan(v)), float(i), 1u)', out)
        self.assertIn('spvDescriptorSet0.t.read(uint2(1),0)', out)
        self.assertEqual(bindings[1]['reduce'], 1)

    def test_rejects_implicit_lod_and_offsets(self):
        for args in ('s,uv', 's,uv,level(0),int2(1)'):
            with self.assertRaises(ValueError):
                dmsh_reduce.apply('spvDescriptorSet0.t.sample('+args+')', self.bindings(), {17: 1})

    def test_rejects_unknown_texture_contract(self):
        for typ in ('depth2d<float>', 'texture2d<half>', 'texture2d_array<float>'):
            bindings = self.bindings(); bindings[0]['msl_type'] = typ
            with self.assertRaises(ValueError):
                dmsh_reduce.apply('', bindings, {17: 1})
        with self.assertRaises(ValueError):
            dmsh_reduce.apply('', self.bindings(), {18: 1})

    def test_disabled_is_unchanged(self):
        bindings = self.bindings(); before = copy.deepcopy(bindings)
        self.assertEqual(dmsh_reduce.apply('unchanged', bindings, {}), 'unchanged')
        self.assertEqual(bindings, before)

    def test_gpu(self):
        with tempfile.TemporaryDirectory(prefix='nvn-reduce-') as directory:
            helper = pathlib.Path(directory) / 'helper.metal'
            helper.write_text(dmsh_reduce.MSL)
            subprocess.run([str(HERE / 't_reduce'), str(helper)], check=True)


if __name__ == '__main__':
    unittest.main()

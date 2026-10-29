"""Compute kernels from Unity 2019, 2020 and 2022 must coexist in one reader."""
import ast
import json
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch


class ComputeVariants(unittest.TestCase):
    def extract(self, kernel):
        path = Path(__file__).resolve().parents[1] / 'tools/shader_split.py'
        function = next(n for n in ast.parse(path.read_text()).body if isinstance(n, ast.FunctionDef) and n.name == 'unity_compute')
        source = types.SimpleNamespace(CLASS_COMPUTE_SHADER=72, NoTree=type('NoTree', (Exception,), {}),
            serialized_objects=lambda *args: [(72, 1, {'m_Name': 'Compute', 'variants': [{'kernels': [kernel]}]})])
        namespace = {'json': json, 'skey': lambda ctl, code: 'fixture', 'COMMON': (), 'TREES': True, 'unity_program': lambda code, where, stage: [(stage, b'control', code)]}
        exec(compile(ast.Module(body=[function], type_ignores=[]), str(path), 'exec'), namespace)
        with patch.dict(sys.modules, unityfs=source):
            return [row[3] for row in namespace['unity_compute'](b'', 'asset', {})]

    def test_2019_direct_kernel(self):
        self.assertEqual(self.extract({'name': 'Skin', 'code': b'2019'}), [b'2019'])

    def test_2020_keyword_map(self):
        self.assertEqual(self.extract({'name': 'Skin', 'variantMap': [{'first': 'A', 'second': {'code': b'A'}}, {'first': 'B', 'second': {'code': b'B'}}]}), [b'A', b'B'])

    def test_2022_deduplicated_variants(self):
        self.assertEqual(self.extract({'name': 'Skin', 'uniqueVariants': [{'code': b'A'}, {'code': b'B'}]}), [b'A', b'B'])


if __name__ == '__main__':
    unittest.main()

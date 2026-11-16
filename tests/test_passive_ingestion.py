"""Passive ingestion reads local MATs and preserves replay/source trial links."""
import ast
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import Mock

import numpy as np
from scipy.io import loadmat, savemat

from helpers import ROOT, parser_namespace, replay_data


class Relation:
    def __init__(self, rows):
        self.rows = rows

    def __call__(self):
        return self

    def __and__(self, restriction):
        if isinstance(restriction, str):
            assert restriction == 'file_path LIKE "%.mat"'
            return Relation([r for r in self.rows if r['file_path'].endswith('.mat')])
        keys = restriction if isinstance(restriction, list) else [restriction]
        return Relation([r for r in self.rows if any(all(
            r[k] == v for k, v in key.items() if k in r) for key in keys)])

    def fetch1(self, field):
        assert len(self.rows) == 1
        return self.rows[0][field]

    def fetch(self, **kwargs):
        return self.rows

    def local_path(self):
        return self.fetch1('local_path')


class PassiveIngestionTest(unittest.TestCase):
    def run_make(self, filename):
        key = dict(subject_name='GRB001', session_name='one', dataset_name='chipmunk_passive')
        dataset = Relation([dict(key, dataset_type='passive-stimulation')])
        dataset.DataFiles = Relation([dict(key, file_path='replay.mat')])
        file_relation = Relation([dict(file_path='replay.mat', local_path=filename)])
        file_factory = lambda: file_relation
        target = SimpleNamespace(insert1=Mock(), Trial=SimpleNamespace(insert=Mock()))
        cls = next(n for n in ast.parse((ROOT / 'pluginschema.py').read_text()).body
                   if isinstance(n, ast.ClassDef) and n.name == 'ChipmunkPassive')
        make = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == 'make')
        make.body = [n for n in make.body if not isinstance(n, ast.ImportFrom)]
        ns = dict(Dataset=dataset, File=file_factory, np=np, loadmat=loadmat,
                  _passive_replay=parser_namespace()['_passive_replay'])
        exec(compile(ast.Module(body=[make], type_ignores=[]), 'passive_make', 'exec'), ns)
        ns['make'](target, key)
        return target

    def test_missing_local_mat_fails_without_downloading(self):
        with self.assertRaisesRegex(FileNotFoundError, 'Passive MAT is not local'):
            self.run_make(None)

    def test_local_mat_imports_replay_and_source_links(self):
        replay = replay_data(['completed', 'completed'], 'completed')['PassiveReplay']
        replay['order'] = 'sequential'
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'replay.mat'
            savemat(path, {'PassiveReplay': replay}, long_field_names=True)
            target = self.run_make(str(path))
        target.insert1.assert_called_once()
        rows = target.Trial.insert.call_args.args[0]
        self.assertEqual([r['source_trial_num'] for r in rows], [0, 1])
        self.assertTrue(all(r['source_dataset_name'] == 'chipmunk' for r in rows))
        self.assertEqual([r['t_sync'] for r in rows], [100., 102.])

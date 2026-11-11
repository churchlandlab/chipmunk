import sys
import unittest
from datetime import date
from pathlib import Path
from unittest import mock

from test_integration import _import_data_with_real_libs


def test_labdata_import_precedes_chipmunk_import() -> None:
    source = (
        Path(__file__).parents[2] / "labdata_plugin" / "dashboard" / "data.py"
    ).read_text(encoding="utf-8")
    assert (
        source.index("import labdata")
        < source.index("from labdata.schema")
        < source.index("from chipmunk import Chipmunk")
    )


class _Cacheable:
    def __init__(self) -> None:
        self.cache_clear = mock.Mock()


class TestDataUtilities(unittest.TestCase):
    def setUp(self) -> None:
        self.addCleanup(lambda: sys.modules.pop("dashboard.data", None))
        self.data = _import_data_with_real_libs()

    def test_ttl_lru_cache_reuses_value_within_bucket_and_expires(self) -> None:
        calls = {"count": 0}

        @self.data._ttl_lru_cache(maxsize=8, ttl_seconds=10)
        def cached(x):
            calls["count"] += 1
            return x * 2

        with mock.patch.object(self.data.time, "time", return_value=5):
            self.assertEqual(cached(3), 6)
            self.assertEqual(cached(3), 6)
        self.assertEqual(calls["count"], 1)

        with mock.patch.object(self.data.time, "time", return_value=25):
            self.assertEqual(cached(3), 6)
        self.assertEqual(calls["count"], 2)

        cached.cache_clear()
        with mock.patch.object(self.data.time, "time", return_value=25):
            self.assertEqual(cached(3), 6)
        self.assertEqual(calls["count"], 3)

    def test_clear_data_cache_clears_all_registered_caches(self) -> None:
        attrs = [
            "get_all_subjects",
            "get_subjects_with_recent_sessions",
            "get_subject_data",
            "get_session_trials",
            "get_subject_water",
            "get_trials_for_sessions",
            "get_wait_medians_for_sessions",
            "get_sessions",
            "get_subjects_for_date",
            "session_metrics",
            "multisession_metrics",
        ]
        fakes = {name: _Cacheable() for name in attrs}

        with mock.patch.multiple(self.data, **fakes):
            self.data.clear_data_cache()

        for fake in fakes.values():
            fake.cache_clear.assert_called_once()

    def test_get_trials_for_sessions_returns_empty_for_no_session_names(self) -> None:
        self.assertEqual(self.data.get_trials_for_sessions("subject-a", ()), {})

    def test_get_wait_medians_for_sessions_returns_empty_for_no_session_names(
        self,
    ) -> None:
        self.assertEqual(self.data.get_wait_medians_for_sessions("subject-a", ()), {})

    def test_get_all_subjects_returns_sorted_unique_values(self) -> None:
        trialset = mock.Mock()
        trialset.fetch.return_value = ["z", "a", "z", "b"]
        trialset_cls = mock.Mock(return_value=trialset)

        with mock.patch.object(self.data.DecisionTask, "TrialSet", trialset_cls):
            result = self.data.get_all_subjects()

        self.assertEqual(result, ["a", "b", "z"])
        trialset.fetch.assert_called_once_with("subject_name")

    def test_get_subjects_with_recent_sessions_filters_at_query(self) -> None:
        self.data.get_subjects_with_recent_sessions.cache_clear()
        rel = mock.Mock()
        rel.fetch.return_value = ["subject-b", "subject-a", "subject-a"]
        trialset = mock.MagicMock()
        trialset.__and__.return_value = rel
        trialset_cls = mock.Mock(return_value=trialset)

        with (
            mock.patch.object(self.data.DecisionTask, "TrialSet", trialset_cls),
            mock.patch.object(self.data, "date") as fake_date,
        ):
            fake_date.today.return_value = date(2026, 1, 20)
            result = self.data.get_subjects_with_recent_sessions(days=14)

        trialset.__and__.assert_called_once_with("session_name >= '20260106'")
        rel.fetch.assert_called_once_with("subject_name")
        self.assertEqual(result, {"subject-a", "subject-b"})

    def test_get_sessions_returns_list_from_fetch(self) -> None:
        rel = mock.Mock()
        rel.fetch.return_value = ("20260101_010101", "20260102_010101")
        trialset = mock.MagicMock()
        trialset.__and__.return_value = rel
        trialset_cls = mock.Mock(return_value=trialset)

        with mock.patch.object(self.data.DecisionTask, "TrialSet", trialset_cls):
            result = self.data.get_sessions("subject-a")

        self.assertEqual(result, ["20260101_010101", "20260102_010101"])
        rel.fetch.assert_called_once_with("session_name", order_by="session_name")

    def test_get_subjects_for_date_filters_at_query(self) -> None:
        self.data.get_subjects_for_date.cache_clear()
        rel = mock.Mock()
        rel.fetch.return_value = ["subject-b", "subject-a", "subject-a"]
        trialset = mock.MagicMock()
        trialset.__and__.return_value = rel
        trialset_cls = mock.Mock(return_value=trialset)

        with mock.patch.object(self.data.DecisionTask, "TrialSet", trialset_cls):
            result = self.data.get_subjects_for_date("20260106")

        trialset.__and__.assert_called_once_with("session_name LIKE '20260106%'")
        rel.fetch.assert_called_once_with("subject_name")
        self.assertEqual(result, ["subject-a", "subject-b"])

    def test_get_subject_data_returns_dataframe_from_fetch(self) -> None:
        self.data.get_subject_data.cache_clear()
        rows = [{"subject_name": "subject-a", "session_name": "20260101_010101"}]
        rel = mock.Mock()
        rel.fetch.return_value = rows
        trialset = mock.MagicMock()
        trialset.__and__.return_value = rel
        trialset_cls = mock.Mock(return_value=trialset)

        with mock.patch.object(self.data.DecisionTask, "TrialSet", trialset_cls):
            result = self.data.get_subject_data("subject-a")

        self.assertEqual(result.to_dict("records"), rows)
        trialset.__and__.assert_called_once_with("subject_name = 'subject-a'")
        rel.fetch.assert_called_once()
        self.assertEqual(rel.fetch.call_args.kwargs["order_by"], "session_name")
        self.assertTrue(rel.fetch.call_args.kwargs["as_dict"])

    def test_get_subject_data_falls_back_when_fetch_raises(self) -> None:
        self.data.get_subject_data.cache_clear()
        rel = mock.Mock()
        rel.fetch.side_effect = RuntimeError("boom")
        trialset = mock.MagicMock()
        trialset.__and__.return_value = rel
        trialset_cls = mock.Mock(return_value=trialset)

        with (
            mock.patch.object(self.data.DecisionTask, "TrialSet", trialset_cls),
            mock.patch.object(
                self.data.pd, "DataFrame", side_effect=lambda x: {"source": x}
            ),
        ):
            result = self.data.get_subject_data("subject-b")

        self.assertEqual(result, {"source": rel})

    def test_get_session_trials_fetches_by_subject_and_session(self) -> None:
        self.data.get_session_trials.cache_clear()

        class _Rel:
            def __init__(self) -> None:
                self.restriction = None
                self.order_by = None
                self.Trial = object()
                self.TrialParameters = object()

            def __mul__(self, _other):
                return self

            def __and__(self, restriction):
                self.restriction = restriction
                return self

            def fetch(self, order_by=None):
                self.order_by = order_by
                return [{"trial_num": 1}]

        rel = _Rel()
        with mock.patch.object(self.data, "Chipmunk", rel):
            result = self.data.get_session_trials("subject-a", "20260101_010101")

        self.assertEqual(result.to_dict("records"), [{"trial_num": 1}])
        self.assertEqual(
            rel.restriction,
            "subject_name = 'subject-a' AND session_name = '20260101_010101'",
        )
        self.assertEqual(rel.order_by, "trial_num")

    def test_get_subject_water_converts_values_to_float(self) -> None:
        self.data.get_subject_water.cache_clear()

        class _Rel:
            def __init__(self) -> None:
                self.restriction = None

            def __mul__(self, _other):
                return self

            def __and__(self, restriction):
                self.restriction = restriction
                return self

            def fetch(self, *_args, **_kwargs):
                return [
                    {"session_name": "s1", "water_volume": "1.5"},
                    {"session_name": "s2", "water_volume": 2},
                ]

        rel = _Rel()
        with (
            mock.patch.object(self.data, "DecisionTask", rel),
            mock.patch.object(self.data, "Watering", object()),
        ):
            result = self.data.get_subject_water("subject-a")

        self.assertEqual(result, {"s1": 1.5, "s2": 2.0})
        self.assertEqual(rel.restriction, "subject_name = 'subject-a'")

    def test_session_metrics_returns_none_for_empty_trials(self) -> None:
        self.data.session_metrics.cache_clear()

        class _EmptyTrials:
            empty = True

        with mock.patch.object(
            self.data, "get_session_trials", return_value=_EmptyTrials()
        ):
            result = self.data.session_metrics("subject-a", "20260101_010101")

        self.assertIsNone(result)

    def test_multisession_metrics_returns_none_for_empty_subject_data(self) -> None:
        self.data.multisession_metrics.cache_clear()

        class _EmptySubjectData:
            empty = True

            def copy(self):
                return self

        with mock.patch.object(
            self.data, "get_subject_data", return_value=_EmptySubjectData()
        ):
            result = self.data.multisession_metrics("subject-a", sessions_back=5)

        self.assertIsNone(result)

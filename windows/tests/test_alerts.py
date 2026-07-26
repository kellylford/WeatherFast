import unittest
from datetime import datetime, timedelta, timezone

from fastweather.models import alert as A
from fastweather.services import alert_service, nws
from fastweather.ui import alert_format as F


def _future(hours=6):
    return (datetime.now(timezone.utc) + timedelta(hours=hours)).isoformat()


def _past(hours=6):
    return (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()


class HazardTests(unittest.TestCase):
    def test_classification_order(self):
        cases = {
            "Tornado Warning": "Storms",
            "Hurricane Warning": "Tropical",
            "Winter Storm Warning": "Winter",   # winter before storms/heat
            "Excessive Heat Warning": "Heat",
            "Air Quality Alert": "Air Quality",
            "Flood Warning": "Flooding",
            "High Wind Warning": "Wind",
            "Small Craft Advisory": "Marine & Coastal",
            "Dense Fog Advisory": "Fog",
            "Rip Current Statement": "Marine & Coastal",
        }
        for event, expected in cases.items():
            self.assertEqual(A.classify_hazard(event), expected, event)


class SeverityFilterTests(unittest.TestCase):
    def test_exclusive(self):
        self.assertTrue(A.severity_filter_includes("All", "Minor"))
        self.assertTrue(A.severity_filter_includes("Severe", "Severe"))
        self.assertFalse(A.severity_filter_includes("Severe", "Extreme"))
        self.assertFalse(A.severity_filter_includes("Moderate", "Severe"))


class DigestTests(unittest.TestCase):
    def _mk(self, event, sev, area):
        return A.WeatherAlert(event, sev, "", "", "", "", _future(), area)

    def test_group_and_sort(self):
        alerts = [
            self._mk("Flood Warning", "Severe", "A"),
            self._mk("Flood Warning", "Severe", "B"),
            self._mk("Tornado Warning", "Extreme", "C"),
        ]
        groups = A.build_digest(alerts, "All", None)
        # Extreme first despite fewer areas
        self.assertEqual(groups[0].event, "Tornado Warning")
        self.assertEqual(groups[0].count, 1)
        self.assertEqual(groups[1].event, "Flood Warning")
        self.assertEqual(groups[1].count, 2)

    def test_severity_filter(self):
        alerts = [self._mk("Flood Warning", "Severe", "A"),
                  self._mk("Heat Advisory", "Minor", "B")]
        groups = A.build_digest(alerts, "Severe", None)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0].severity, "Severe")

    def test_hazard_filter(self):
        alerts = [self._mk("Flood Warning", "Severe", "A"),
                  self._mk("High Wind Warning", "Severe", "B")]
        groups = A.build_digest(alerts, "All", "Flooding")
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0].event, "Flood Warning")


class ExpiryTests(unittest.TestCase):
    def test_expired(self):
        a = A.WeatherAlert("X", "Severe", "", "", "", "", _past(), "")
        self.assertTrue(a.is_expired())

    def test_active(self):
        a = A.WeatherAlert("X", "Severe", "", "", "", "", _future(), "")
        self.assertFalse(a.is_expired())

    def test_no_end_kept(self):
        a = A.WeatherAlert("X", "Severe", "", "", "", "", "", "")
        self.assertFalse(a.is_expired())


class NWSParseTests(unittest.TestCase):
    def test_parse_and_area_labeling(self):
        feature = {"properties": {
            "id": "x1", "event": "Flood Warning", "severity": "Severe",
            "areaDesc": "Dane", "onset": _past(1), "ends": _future(),
            "geocode": {"UGC": ["WIC025", "WIC021"]},
        }}
        a = nws.parse_feature(feature)
        self.assertEqual(a.severity, "Severe")
        self.assertEqual(a.area, "Dane, WI")
        self.assertEqual(a.source, "NWS")

    def test_air_quality_severity_promotion(self):
        feature = {"properties": {"event": "Air Quality Alert", "severity": "Unknown",
                                  "areaDesc": "Zone", "ends": _future()}}
        self.assertEqual(nws.parse_feature(feature).severity, "Moderate")

    def test_ends_clamped_to_onset(self):
        feature = {"properties": {"event": "X", "onset": _future(5), "ends": _future(1),
                                  "areaDesc": "Z"}}
        a = nws.parse_feature(feature)
        self.assertEqual(a.ends, a.onset)  # ends before onset -> clamped


class AlertServiceTests(unittest.TestCase):
    def setUp(self):
        self._orig = alert_service.http.get_json

    def tearDown(self):
        alert_service.http.get_json = self._orig

    def test_filters_expired_and_sorts(self):
        alert_service.http.get_json = lambda *a, **k: {"features": [
            {"properties": {"event": "Old", "severity": "Extreme", "areaDesc": "A",
                            "ends": _past()}},
            {"properties": {"event": "Minor Now", "severity": "Minor", "areaDesc": "B",
                            "ends": _future()}},
            {"properties": {"event": "Severe Now", "severity": "Severe", "areaDesc": "C",
                            "ends": _future()}},
        ]}
        alerts = alert_service.fetch_alerts(9.0, 9.0, use_cache=False)
        self.assertEqual([a.event for a in alerts], ["Severe Now", "Minor Now"])

    def test_failure_raises(self):
        # Callers must be able to tell "couldn't check" from "no alerts".
        def boom(*a, **k):
            raise RuntimeError("down")
        alert_service.http.get_json = boom
        with self.assertRaises(RuntimeError):
            alert_service.fetch_alerts(9.0, 9.0, use_cache=False)


class CityRowBadgeTests(unittest.TestCase):
    def _mk(self, event, sev):
        return A.WeatherAlert(event, sev, "", "", "", "", _future(), "Area")

    def test_no_alerts_no_badge(self):
        self.assertEqual(F.city_row_badge([]), "")

    def test_names_worst_alert(self):
        badge = F.city_row_badge([self._mk("Frost Advisory", "Minor"),
                                  self._mk("Tornado Warning", "Extreme")])
        self.assertIn("EXTREME", badge)
        self.assertIn("Tornado Warning", badge)

    def test_counts_the_rest(self):
        alerts = [self._mk("Tornado Warning", "Extreme"),
                  self._mk("Flood Warning", "Severe"),
                  self._mk("Frost Advisory", "Minor")]
        self.assertIn("+2 more", F.city_row_badge(alerts))
        self.assertNotIn("more", F.city_row_badge(alerts[:1]))


class UnwrapTests(unittest.TestCase):
    # NWS hard-wraps at ~68 columns, mid-sentence.
    NWS = ("* WHAT...Heat index values of 100 to 103 degrees expected.\n\n"
           "* IMPACTS...Hot temperatures and high humidity may cause heat\n"
           "illnesses.\n\n"
           "* ADDITIONAL DETAILS...Areas along the immediate Lake Michigan\n"
           "shoreline may see some relief.\n&&")

    def test_sentence_is_not_split(self):
        paras = F.unwrap(self.NWS)
        self.assertIn("* IMPACTS...Hot temperatures and high humidity may cause "
                      "heat illnesses.", paras)
        # No row is a stranded fragment of the previous sentence.
        self.assertNotIn("illnesses.", paras)

    def test_one_paragraph_per_bullet(self):
        self.assertEqual(len(F.unwrap(self.NWS)), 3)

    def test_bullets_split_without_blank_lines(self):
        paras = F.unwrap("* WHAT...Rain.\n* WHERE...Dane.")
        self.assertEqual(paras, ["* WHAT...Rain.", "* WHERE...Dane."])

    def test_product_delimiters_dropped(self):
        self.assertNotIn("&&", F.unwrap(self.NWS))
        self.assertNotIn("$$", F.unwrap("Stay hydrated.\n$$"))

    def test_empty(self):
        self.assertEqual(F.unwrap(""), [])
        self.assertEqual(F.unwrap(None), [])


class SectionLinesTests(unittest.TestCase):
    def _mk(self, event, sev):
        return A.WeatherAlert(event, sev, "", "", "", "", _future(), "Area")

    def test_off_is_omitted_entirely(self):
        self.assertEqual(F.section_lines("off"), ([], {}))

    def test_error_is_never_no_alerts(self):
        lines, actions = F.section_lines("error", [], "down")
        text = " ".join(lines)
        self.assertIn("Could not check", text)
        self.assertNotIn("No active alerts", text)
        self.assertIn(F.RETRY, actions.values())

    def test_empty_says_no_alerts(self):
        lines, actions = F.section_lines("ok", [])
        self.assertIn("No active alerts.", lines)
        self.assertEqual(actions, {})

    def test_alert_rows_are_actionable(self):
        alerts = [self._mk("Tornado Warning", "Extreme"), self._mk("Flood Warning", "Severe")]
        lines, actions = F.section_lines("ok", alerts)
        # Header then the alerts themselves - no count/instruction preamble.
        self.assertEqual(lines[0], "ALERTS")
        self.assertTrue(lines[1].startswith("EXTREME: Tornado Warning"))
        # Every mapped index points at that alert's own row.
        self.assertEqual(len(actions), 2)
        for idx, alert in actions.items():
            self.assertIn(alert.event, lines[idx])


if __name__ == "__main__":
    unittest.main()

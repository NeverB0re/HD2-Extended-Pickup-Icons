"""Count fake-engine native reads against a Git baseline; this is not an FPS/frame-time benchmark.

Run from the repo root with lupa installed: python -B tools/compare_discovery_reads.py
The test harness needs an ASCII writable TEMP on Windows (Lua 5.1's file I/O).
"""
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
sys.path.insert(0, str(ROOT))
import build
from test_extended_pickup_icons_range import AVATAR, TEST_ICONS, DrawingTests, unit


def baseline_source(ref):
    source = subprocess.check_output(
        ["git", "show", ref + ":src/extended_pickup_icons_range.lua"], cwd=ROOT
    ).decode("utf-8")
    source = source.replace('"@TARGETS@"', "(function()\n" + Path(build.TARGETS).read_text(encoding="utf-8") + "end)()")
    source = source.replace('"@LOCAL_PLAYER@"', "(function()\n" + Path(build.LOCAL_PLAYER).read_text(encoding="utf-8") + "\nend)()")
    return source.replace('"@ICONS@"', TEST_ICONS)


def count_reads(source, scenario):
    case = DrawingTests()
    case.setUp()
    try:
        if source is not None:
            case.source = source
        case.set_units(AVATAR, [unit(0, -8)], loaded=False)
        rows = [r for r in case.targets() if r.get("name") and r["group"] in ("samples", "supplies", "mission")]
        for i, row in enumerate(rows[:10]):
            case.set_units(row["name"], [unit(i * 0.1, 12 if scenario != "far" else 300)])
        if scenario == "vehicle":
            case.set_units("content/fac_helldivers/vehicles/frv/frv", [unit(0, 30)])
            case.set_units("content/fac_helldivers/vehicles/frv/armaments/frv_mg/frv_mg", [unit(0, 30, 1.5)])
        case.lua.execute("""
            local fake = ...
            local position = fake.chef.unit_position
            fake.positions = 0
            fake.chef.unit_position = function(...)
                fake.positions = fake.positions + 1
                return position(...)
            end
        """, case.fake)
        case.load()
        case.settle()
        case.frames(120, start=30)
        before = sum(case.fake.lookups.values())
        pos_before = case.fake.positions
        case.frames(240, start=40)
        return {"enumerations": sum(case.fake.lookups.values()) - before,
                "position_reads": case.fake.positions - pos_before, "markers": case.dots()}
    finally:
        case.doCleanups()


if __name__ == "__main__":
    ref = sys.argv[1] if len(sys.argv) > 1 else "483270b"
    baseline = baseline_source(ref)
    results = {scenario: {"baseline": count_reads(baseline, scenario), "current": count_reads(None, scenario)}
               for scenario in ("near", "far", "vehicle")}
    for row in results.values():
        assert row["baseline"]["markers"] == row["current"]["markers"]
        assert row["current"]["enumerations"] <= row["baseline"]["enumerations"]
    print(json.dumps({"baseline": ref, "frames": 240, "scenarios": results}, indent=2))

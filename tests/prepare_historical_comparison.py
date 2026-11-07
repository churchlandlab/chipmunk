"""Prepare pinned public source snapshots and verbatim stimulus/staircase blocks.

Animal MAT recordings must be supplied separately under OUTPUT/recordings.
Requires git and, for snapshots absent locally, an authenticated GitHub CLI.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

SOURCES = {
    "solo_base": (
        "chipmunk_solo",
        "bc8095c02ccd38b875ad493289d414d452b514fe",
        "chipmunk_solo.m",
    ),
    "half_latest": (
        "half_second_chipmunk_solo",
        "0577522f18234ab68f284b7c977d0d5014713c25",
        "half_second_chipmunk_solo.m",
    ),
    "half_2024": (
        "half_second_chipmunk_solo",
        "d14d96a15685f645f53968d0b001fa4cfc7f479c",
        "half_second_chipmunk_solo.m",
    ),
    "original": ("chipmunk", "a112fde94d24b4ca89590081a2aef2d7b4e2e96c", "chipmunk.m"),
    "ephys": (
        "half_second_chipmunk_ephys",
        "a451cf9cbe50bf40c2b05333d7333887cda77988",
        "half_second_chipmunk_ephys.m",
    ),
}


def prepare(output, current):
    output.mkdir(parents=True, exist_ok=True)
    versions = {"current": (current, "chipmunk_solo.m")}
    provenance = {}
    for label, (repo, sha, main) in SOURCES.items():
        local = subprocess.run(
            ["git", "cat-file", "-e", sha], cwd=current, capture_output=True
        )
        if local.returncode == 0:
            blob = subprocess.check_output(["git", "archive", sha], cwd=current)
        else:
            blob = subprocess.check_output(
                ["gh", "api", f"repos/churchlandlab/{repo}/tarball/{sha}"]
            )
        destination = output / "sources" / label
        destination.mkdir(parents=True, exist_ok=True)
        with tarfile.open(fileobj=io.BytesIO(blob), mode="r:*") as archive:
            for member in archive.getmembers():
                path = Path(member.name)
                if local.returncode != 0:
                    path = Path(*path.parts[1:])  # GitHub's archive wrapper directory.
                assert not path.is_absolute() and ".." not in path.parts
                if member.isfile() and path.suffix in {".m", ".mat"}:
                    target = destination / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.extractfile(member).read())
        versions[label] = destination, main
        provenance[label] = {"repository": f"churchlandlab/{repo}", "commit": sha}

    generated = output / "generated"
    generated.mkdir(exist_ok=True)
    manifest = []
    for label, (folder, main) in versions.items():
        source = (folder / main).read_text()
        # Both bounds are checked against immutable snapshots. Extract code,
        # rather than reimplementing the algorithms under comparison.
        start = list(re.finditer(r"^\s*stimTrainDuration\s*=\s*1\s*;", source, re.M))[
            -1
        ].start()
        pulse = source.rfind("stimulusDuration = 0.015", 0, start)
        if pulse >= 0 and start - pulse < 150:
            start = source.rfind("\n", 0, pulse) + 1
        end = (
            start
            + re.search(
                r"PsychToolboxSoundServer\('Load',\s*1,\s*stimTrainSignals\);",
                source[start:],
            ).end()
        )
        lines = source[start:end].splitlines()
        body = "\n".join(
            line
            for line in lines
            if not line.lstrip().startswith("%")
            and "StimulusPlotDemonstrator(" not in line
            and "PsychToolboxSoundServer('Load'" not in line
        )
        marker = "function [visualIsiList, auditoryIsiList] = assignModalityIsi"
        helper = source[source.index(marker) :] if marker in source else ""
        function = "historical_stim_" + label
        header = (
            f"function signal={function}(stimulusRate,modality)\nglobal BpodSystem\n"
            "SamplingFreq=192000; currentTrial=1; ModalityRecord=modality; "
            "categoryBoundary=12; visualIsiList=NaN; auditoryIsiList=NaN;\n"
        )
        (generated / (function + ".m")).write_text(
            header + body + "\nsignal=stimTrainSignals;\nend\n" + helper
        )

        source_lines = source.splitlines()
        start = next(
            i
            for i, line in enumerate(source_lines)
            if "if strcmpi(S.minWaitTime,'Exp')" in line
        )
        depth = 0
        body = []
        for line in source_lines[start:]:
            code = line.split("%", 1)[0].strip()
            if code.startswith("if "):
                depth += 1
            if re.match(r"^end\b", code):
                depth -= 1
            body.append(line)
            if depth == 0:
                break
        assert depth == 0
        (generated / ("historical_step_" + label + ".m")).write_text(
            "function S=historical_step_" + label + "(S,outcome)\nglobal BpodSystem\n"
            "TrialsDone=1; BpodSystem.Data.OutcomeRecord=outcome;\n"
            + "\n".join(body)
            + "\nend\n"
        )
        manifest.append(
            {
                "label": label,
                "main_sha256": hashlib.sha256((folder / main).read_bytes()).hexdigest(),
                **provenance.get(
                    label,
                    {
                        "repository": "current working tree",
                        "commit": subprocess.check_output(
                            ["git", "rev-parse", "HEAD"], cwd=current, text=True
                        ).strip(),
                    },
                ),
                "functions_source": "half_latest" if label == "ephys" else label,
            }
        )

    fixture = current / "tests" / "fixtures"
    shutil.copytree(
        fixture / "historical_comparison", output / "capture", dirs_exist_ok=True
    )
    shutil.copyfile(
        fixture / "trial_data" / "AddTrialEvents.m",
        output / "capture" / "AddTrialEvents.m",
    )
    (output / "wrapper-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {len(versions)} source versions in {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    prepare(args.output.resolve(), Path(__file__).resolve().parents[1])

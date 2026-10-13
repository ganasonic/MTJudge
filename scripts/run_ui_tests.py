#!/usr/bin/env python3
"""Build, install and run a selected UI suite on one explicitly named iOS device."""
import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
SUITES = {
    "smoke": ["testLaunchShowsTabBar"],
    "navigation": ["testLaunchShowsTabBar", "testTabSwitching", "testCameraSettingsNavigation"],
    "camera": ["testCameraManualRecordingStartStop", "testWaterJumpAutomaticRecordingOnDevice"],
}
SUITES["all"] = SUITES["navigation"] + SUITES["camera"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Physical device UDID (never auto-selected)")
    parser.add_argument("--suite", choices=SUITES, default="smoke")
    parser.add_argument("--output", type=Path, default=Path("/tmp/MTJudgeUITestRuns"))
    parser.add_argument("--allow-provisioning-updates", action="store_true")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]+", args.device):
        parser.error("Invalid device identifier")
    run_id = datetime.datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6]
    out = args.output.resolve() / run_id
    out.mkdir(parents=True)
    print(f"Artifacts: {out}", flush=True)
    env = dict(os.environ, DEVELOPER_DIR=os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"))
    report = {"runID": run_id, "device": args.device, "suite": args.suite,
              "expectedTests": SUITES[args.suite], "status": "not_run", "steps": []}
    bundle = out / "TestResults.xcresult"

    def run(name, command, timeout=120):
        print(f"{name}: {shlex.join(command)}", flush=True)
        with (out / f"{name}.log").open("w") as log:
            process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = 124
        report["steps"].append({"name": name, "command": command, "exitCode": code})
        print(f"{name}: exit {code}", flush=True)
        return code

    lock = open(f"/tmp/mtjudge-ui-{args.device}.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        run("xcode-version", ["xcrun", "xcodebuild", "-version"])
        code = run("device", ["xcrun", "devicectl", "device", "info", "details", "--device", args.device,
                              "--timeout", "30", "--json-output", str(out / "device.json")], 45)
        if code:
            report["status"] = "environment_failed"
            return 2
        source = out / "source"
        source.mkdir()
        for name in ["MTJudge", "MTJudge.xcodeproj", "MTJudgeTests", "MTJudgeUITests", "MTJudgeWatch", "resource"]:
            shutil.copytree(ROOT / name, source / name, ignore=shutil.ignore_patterns("xcuserdata", "*.xcuserstate"))
        common = ["xcrun", "xcodebuild", "-project", str(source / "MTJudge.xcodeproj"), "-scheme", "MTJudge",
                  "-configuration", "Debug", "-destination", f"platform=iOS,id={args.device}",
                  "-destination-timeout", "60", "-derivedDataPath", str(out / "DerivedData"),
                  "-parallel-testing-enabled", "NO", "CODE_SIGN_IDENTITY=Apple Development",
                  "IPHONEOS_DEPLOYMENT_TARGET=17.6"]
        selection = [f"-only-testing:MTJudgeUITests/MTJudgeUITests/{name}" for name in SUITES[args.suite]]
        if args.allow_provisioning_updates:
            common.append("-allowProvisioningUpdates")
        if run("build", common + selection + ["build-for-testing"], 900):
            report["status"] = "build_failed"
            return 3
        code = run("test", common + selection + ["-resultBundlePath", str(bundle),
                   "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "180",
                   "test-without-building"], 900)
        report["status"] = "test_failed" if code else "result_unverified"
        if bundle.exists():
            summary_code = run("summary", ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(bundle)])
            run("attachments", ["xcrun", "xcresulttool", "export", "attachments", "--path", str(bundle),
                                "--output-path", str(out / "attachments")])
            run("diagnostics", ["xcrun", "xcresulttool", "export", "diagnostics", "--path", str(bundle),
                                "--output-path", str(out / "diagnostics")])
            if not summary_code:
                summary = json.loads((out / "summary.log").read_text())
                report["testSummary"] = summary
                if (code == 0 and summary.get("passedTests", 0) == len(selection)
                        and summary.get("failedTests", 0) == 0 and summary.get("skippedTests", 0) == 0):
                    report["status"] = "passed"
        return 0 if report["status"] == "passed" else 4
    except Exception as error:
        report["status"] = "runner_failed"
        report["error"] = str(error)
        return 5
    finally:
        (out / "run.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
        print(f"Result: {report['status']} ({out / 'run.json'})", flush=True)
        lock.close()


if __name__ == "__main__":
    sys.exit(main())

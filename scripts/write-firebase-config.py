import json
import os
from pathlib import Path


def main():
    configs = {}
    project_ids = set()
    for role in ("parent", "child"):
        variable = f"FIREBASE_{role.upper()}_CONFIG"
        raw = os.environ.get(variable)
        if not raw:
            raise SystemExit(f"Missing {variable}")
        config = json.loads(raw)
        package = f"com.safeguard.app.{role}"
        packages = [
            client.get("client_info", {})
            .get("android_client_info", {})
            .get("package_name")
            for client in config.get("client", [])
        ]
        if package not in packages:
            raise SystemExit(f"{variable} has no registration for {package}")
        project_id = config.get("project_info", {}).get("project_id")
        if not project_id:
            raise SystemExit(f"{variable} has no Firebase project ID")
        project_ids.add(project_id)
        configs[role] = config

    if len(project_ids) != 1:
        raise SystemExit("Parent and Child must use the same Firebase project")

    root = Path(__file__).resolve().parents[1]
    for role, config in configs.items():
        destination = root / "android/app/src" / role / "google-services.json"
        destination.write_text(json.dumps(config, indent=2) + "\n")


if __name__ == "__main__":
    main()

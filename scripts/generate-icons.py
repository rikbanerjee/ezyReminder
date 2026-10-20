"""Legacy entry point for the shared web/iOS icon generator.

Run `npm run icons` instead. Both commands use the approved artwork in
design/app-icon.png and require the project's npm dependencies.
"""

from pathlib import Path
import subprocess


if __name__ == "__main__":
    subprocess.run(
        ["node", str(Path(__file__).with_suffix(".mjs"))],
        check=True,
    )

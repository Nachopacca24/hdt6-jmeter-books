"""Puerta de calidad para un reporte HTML de JMeter.

Uso: python gate.py <carpeta del reporte>

Lee el valor Total de statistics.json y termina con 1 si el p95 pasa de
100 ms o los errores pasan de 1 %. Si los dos quedan dentro, termina con 0.
"""

import json
import sys
from pathlib import Path

P95_MAX_MS = 100.0
ERROR_MAX_PCT = 1.0


def main() -> int:
    if len(sys.argv) != 2:
        print("uso: python gate.py <carpeta del reporte>", file=sys.stderr)
        return 2

    path = Path(sys.argv[1])
    if path.is_dir():
        path = path / "statistics.json"
    if not path.is_file():
        print(f"no existe {path}", file=sys.stderr)
        return 2

    total = json.loads(path.read_text(encoding="utf-8"))["Total"]
    p95 = total["pct2ResTime"]
    errors = total["errorPct"]

    p95_ok = p95 <= P95_MAX_MS
    errors_ok = errors <= ERROR_MAX_PCT
    print(f"p95     {p95:10.2f} ms  límite {P95_MAX_MS:g} ms  {'OK' if p95_ok else 'FALLA'}")
    print(f"errores {errors:10.2f} %   límite {ERROR_MAX_PCT:g} %   {'OK' if errors_ok else 'FALLA'}")

    return 0 if p95_ok and errors_ok else 1


if __name__ == "__main__":
    sys.exit(main())

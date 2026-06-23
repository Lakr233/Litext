# Litext Performance Audit

Generated on 2026-06-23 with `Script/perf_probe.sh` using Xcode 27 beta, release builds, 20 measured iterations, and 5 warmups.

The probe renders a 1,200-line attributed string in a 360 pt container. The resulting CoreText frame contains 3,600 visual lines and has a height of 71,999 pt. The current implementation computes a 900 pt visible window around the middle of the layout and draws only the 46 intersecting lines.

| Checkout | Layout ms | Highlight ms | Full draw ms | Visible draw ms | Visible lines |
| --- | ---: | ---: | ---: | ---: | ---: |
| `main` (`a2ed9b6`) | 16.207 | 21.141 | 15.480 | n/a | n/a |
| PR before visible clipping (`de1e507`) | 15.649 | 20.920 | 15.690 | n/a | n/a |
| Current visible clipping | 16.093 | 20.587 | 14.680 | 0.206 | 46 / 3,600 |

Findings:

- Full-frame drawing did not regress in this local probe. Current full draw was 6.4% faster than the immediately preceding PR commit and 5.2% faster than `main`.
- Layout stayed in the same range as both baselines. The current value is 0.7% faster than `main` and 2.8% slower than `de1e507`, which is within the observed local probe variance.
- Highlight extraction stayed in the same range and was faster than both baselines in this run.
- Visible-rect drawing reduced draw time from 15.690 ms to 0.206 ms against the immediate pre-feature baseline, a 98.7% reduction for this tall-text case.

The raw probe outputs are stored next to this file:

- `main-probe.json`
- `before-visible-probe.json`
- `current-visible-probe.json`

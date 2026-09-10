# References — Performance Testing Methodology

Literature and standards backing the performance-testing approach in
[PERF_TESTING.md](PERF_TESTING.md). Each entry is mapped to the specific testing
action it supports. Sourced from live web searches (Aug 2026), not from memory.

**Provenance legend** — cite according to strength:
`[STD]` international standard · `[PR]` peer-reviewed (journal/conference) ·
`[BOOK]` textbook · `[GREY]` vendor / practitioner grey-literature ·
`[PP]` preprint (not peer-reviewed).

> ⚠ **Verify before you cite.** Bibliographic details marked `[verify]` (some
> DOIs / page numbers) and any numeric thresholds should be confirmed against the
> source itself — several figures here come from search-result summaries, and
> thresholds vary by study/task. The shader-jank / Impeller material in
> `PERF_TESTING.md` has **no** peer-reviewed basis and must be cited as vendor
> documentation, not research.

---

## Stage-by-stage mapping

### Framing — why these metrics at all
- **ISO/IEC 25010** `[STD]` — "Performance efficiency" = *time behaviour* +
  *resource utilization* + *capacity*. Justifies measuring throughput/latency
  (time behaviour), CPU/memory (resource utilization), and client fan-out
  (capacity). → [ISO25000], [ISO]
- **Meier et al. (2007)** `[GREY]` — defines the load/stress/**endurance-soak**/
  spike taxonomy; the basis for naming Stage 3. → [Meier2007]
- **Jain (1991)** `[BOOK]`, **Molyneaux (2014)** `[BOOK]` — metric selection,
  percentiles, measurement discipline. → [Jain1991], [Molyneaux2014]

### Stage 1 & 3 — latency / RTT
- **Miller (1968)** / **Nielsen (1993)** `[PR]`/`[BOOK]` — the 0.1 s / 1 s / 10 s
  responsiveness limits. → [Miller1968], [Nielsen1993]
- **MacKenzie & Ware (1993)** `[PR]` — lag degrades interactive task performance
  (Fitts'-law target acquisition). → [MacKenzieWare1993]

### Stage 1 & 3 — jitter (measured as inter-arrival variation)
- **RFC 3393** `[STD]` — formal definition of jitter as *delay variation*;
  justifies measuring inter-arrival spread rather than mean alone. → [RFC3393]

### The clock-sync ping/pong (offset measurement in the harness + `protocol_run_controller`)
- **RFC 5905 (NTP v4)** `[STD]` — the round-trip offset/delay estimation the code
  performs ("NTP-style"). → [RFC5905]

### Stage 2 — UI smoothness / responsiveness
- **MacKenzie & Ware (1993)**, **Nielsen (1993)** — as above; the perceptual
  basis for a low-latency, smooth UI. (The 60 fps / 16 ms budget itself is
  engine/vendor guidance, not academic.) → [MacKenzieWare1993], [Nielsen1993]

### Stage 3 — endurance / memory-leak detection
- **Huang, Kintala, Kolettis & Fulton (1995)** `[PR]` — foundational software-
  aging work: leaks → resource exhaustion **as uptime grows**; the premise of a
  soak test (watch for monotonic growth). → [Huang1995]
- **"A Survey of Software Aging and Rejuvenation Studies"** `[PR]` — modern
  survey. → [AgingSurvey]

### Clinical justification — why low latency / adequate frame rate matter in telerehab
- **Ye, Zhou, Zhu, Vann & Du (2024)** `[PR]` — teleoperation latency raises
  cognitive load and degrades control; latency >50 ms increases overshoot/
  oscillation. Peer-reviewed support for prioritising low RTT. → [Ye2024]

---

## Full reference list (APA)

- **[ISO25000 / ISO]** International Organization for Standardization. (2011).
  *ISO/IEC 25010:2011 — Systems and software engineering — Systems and software
  Quality Requirements and Evaluation (SQuaRE) — System and software quality
  models.* (Revised as ISO/IEC 25010:2023.)
  https://iso25000.com/index.php/en/iso-25000-standards/iso-25010

- **[Meier2007]** Meier, J. D., Farre, C., Bansode, P., Barber, S., & Rea, D.
  (2007). *Performance Testing Guidance for Web Applications.* Microsoft
  Corporation (patterns & practices).
  https://learn.microsoft.com/en-us/previous-versions/msp-n-p/bb924375(v=pandp.10)

- **[Jain1991]** Jain, R. (1991). *The Art of Computer Systems Performance
  Analysis.* John Wiley & Sons. ISBN 978-0471503361.

- **[Molyneaux2014]** Molyneaux, I. (2014). *The Art of Application Performance
  Testing* (2nd ed.). O'Reilly Media. ISBN 978-1491900543.

- **[Miller1968]** Miller, R. B. (1968). Response time in man-computer
  conversational transactions. *Proceedings of the AFIPS Fall Joint Computer
  Conference, 33*, 267–277. [verify DOI]

- **[Nielsen1993]** Nielsen, J. (1993). *Usability Engineering.* Morgan Kaufmann.
  Summary — "Response Times: The 3 Important Limits":
  https://www.nngroup.com/articles/response-times-3-important-limits/

- **[MacKenzieWare1993]** MacKenzie, I. S., & Ware, C. (1993). Lag as a
  determinant of human performance in interactive systems. *Proceedings of the
  INTERACT '93 and CHI '93 Conference on Human Factors in Computing Systems*,
  488–493. https://doi.org/10.1145/169059.169431

- **[RFC3393]** Demichelis, C., & Chimento, P. (2002). *IP Packet Delay Variation
  Metric for IP Performance Metrics (IPPM)* (RFC 3393). IETF.
  https://www.rfc-editor.org/rfc/rfc3393.html

- **[RFC5905]** Mills, D., Martin, J., Burbank, J., & Kasch, W. (2010). *Network
  Time Protocol Version 4: Protocol and Algorithms Specification* (RFC 5905).
  IETF. https://www.rfc-editor.org/rfc/rfc5905.html

- **[Huang1995]** Huang, Y., Kintala, C., Kolettis, N., & Fulton, N. D. (1995).
  Software rejuvenation: Analysis, module and applications. *Proceedings of the
  25th International Symposium on Fault-Tolerant Computing (FTCS-25)*, 381–390.
  [verify DOI: 10.1109/FTCS.1995.466961]

- **[AgingSurvey]** *A Survey of Software Aging and Rejuvenation Studies.* ACM
  Journal on Emerging Technologies in Computing Systems.
  https://scispace.com/pdf/a-survey-of-software-aging-and-rejuvenation-studies-35l59govpt.pdf
  ⚠ [verify authors/year — likely Cotroneo, Natella, Pietrantuono & Russo, 2014,
  *ACM JETC, 10*(1)]

- **[Ye2024]** Ye, Y., Zhou, T., Zhu, Q., Vann, W., & Du, J. (2024). Brain
  functional connectivity under teleoperation latency: a fNIRS study.
  *Frontiers in Neuroscience, 18*, 1416719.
  https://doi.org/10.3389/fnins.2024.1416719

### Supporting (open the source to confirm details before citing)
- "Are 100 ms Fast Enough? Characterizing Latency Perception Thresholds in
  Mouse-Based Interaction." `[PR]` ⚠ [confirm authors/year/venue]
  https://www.researchgate.net/publication/317801603
- "Examining user performance in the presence of latency and jitter in
  distributed interactive applications." `[PR]` ⚠ [confirm details]
  https://www.researchgate.net/publication/271459380

---

## BibTeX (verified entries; complete the `[verify]` fields before use)

```bibtex
@inproceedings{MacKenzieWare1993,
  author    = {MacKenzie, I. Scott and Ware, Colin},
  title     = {Lag as a Determinant of Human Performance in Interactive Systems},
  booktitle = {Proc. INTERACT '93 and CHI '93 Conf. on Human Factors in Computing Systems},
  pages     = {488--493},
  year      = {1993},
  doi       = {10.1145/169059.169431}
}

@inproceedings{Huang1995,
  author    = {Huang, Yennun and Kintala, Chandra and Kolettis, Nick and Fulton, N. Dudley},
  title     = {Software Rejuvenation: Analysis, Module and Applications},
  booktitle = {Proc. 25th Int. Symp. Fault-Tolerant Computing (FTCS-25)},
  pages     = {381--390},
  year      = {1995},
  note      = {verify DOI: 10.1109/FTCS.1995.466961}
}

@article{Ye2024,
  author  = {Ye, Yang and Zhou, Tianyu and Zhu, Qi and Vann, William and Du, Jing},
  title   = {Brain functional connectivity under teleoperation latency: a fNIRS study},
  journal = {Frontiers in Neuroscience},
  volume  = {18},
  pages   = {1416719},
  year    = {2024},
  doi     = {10.3389/fnins.2024.1416719}
}

@techreport{RFC3393,
  author      = {Demichelis, C. and Chimento, P.},
  title       = {IP Packet Delay Variation Metric for IP Performance Metrics (IPPM)},
  institution = {IETF},
  type        = {RFC},
  number      = {3393},
  year        = {2002},
  url         = {https://www.rfc-editor.org/rfc/rfc3393.html}
}

@techreport{RFC5905,
  author      = {Mills, D. and Martin, J. and Burbank, J. and Kasch, W.},
  title       = {Network Time Protocol Version 4: Protocol and Algorithms Specification},
  institution = {IETF},
  type        = {RFC},
  number      = {5905},
  year        = {2010},
  url         = {https://www.rfc-editor.org/rfc/rfc5905.html}
}

@book{Jain1991,
  author    = {Jain, Raj},
  title     = {The Art of Computer Systems Performance Analysis},
  publisher = {John Wiley \& Sons},
  year      = {1991},
  isbn      = {978-0471503361}
}

@book{Molyneaux2014,
  author    = {Molyneaux, Ian},
  title     = {The Art of Application Performance Testing},
  edition   = {2nd},
  publisher = {O'Reilly Media},
  year      = {2014},
  isbn      = {978-1491900543}
}

@book{Nielsen1993,
  author    = {Nielsen, Jakob},
  title     = {Usability Engineering},
  publisher = {Morgan Kaufmann},
  year      = {1993}
}

@misc{ISO25010,
  author = {{International Organization for Standardization}},
  title  = {ISO/IEC 25010: Systems and software Quality Requirements and Evaluation (SQuaRE)},
  year   = {2011},
  note   = {Revised 2023},
  url    = {https://iso25000.com/index.php/en/iso-25000-standards/iso-25010}
}

@misc{Meier2007,
  author = {Meier, J. D. and Farre, Carlos and Bansode, Prashant and Barber, Scott and Rea, Dennis},
  title  = {Performance Testing Guidance for Web Applications},
  year   = {2007},
  howpublished = {Microsoft patterns \& practices},
  url    = {https://learn.microsoft.com/en-us/previous-versions/msp-n-p/bb924375(v=pandp.10)}
}
```

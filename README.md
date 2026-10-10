# ClearWell

**Turn a confusing well-water lab report into a clear next step.**

About a million Minnesotans drink from private wells, and no agency tests that water for them. When a lab report comes back, it is a page of chemical names and numbers. ClearWell turns it into plain English: what is safe, what is not, who in the household is most at risk, and exactly what to do next.

Built for the Congressional App Challenge, Minnesota's 6th District.

## How it works

1. **Add results.** Photograph the lab report or type the numbers in. Every scanned number must be confirmed before it is saved.
2. **See what they mean.** Each contaminant gets a green, amber or red status, an explanation written for your household, and a "What to do next" step.
3. **Track and act.** History charts show whether water is getting worse, reminders follow the Minnesota Department of Health (MDH) testing schedule, and Get Help lists accredited labs and county contacts.

## The rule that makes it trustworthy

**Colors come only from a fixed table of official EPA and MDH limits** ([OfficialLimits.swift](Clear%20Well/Model/OfficialLimits.swift)), never from AI. The AI (Claude, by Anthropic) does two jobs only: reading numbers from a photo, which the user then confirms, and explaining results in plain language. It cannot change a color, diagnose anyone, or decide whether water is safe, and every red result points to MDH or a certified lab.

## Privacy

Test results stay on the phone. A photo is sent for reading only when the user scans one, and explanations receive only the results and three household answers (baby or pregnant person at home, well age, county). The Claude API key lives on a small server, never in the app.

## Project layout

| Folder | What's inside |
|---|---|
| `Clear Well/Model` | Official limits table, testing schedule, trend math, unit conversion, county resources |
| `Clear Well/Views` | SwiftUI screens: Home, Add Results, Results, History, Get Help, Settings |
| `Clear Well/AI` | Calls to the ClearWell server, plus on-phone fallback explanations |
| `ClearWellTests` | Unit tests for the limits, schedule, trends and conversions |
| `server` | Small TypeScript server that calls Claude ([setup guide](server/README.md)) |
| `docs` | Planning documents and a sample lab report for testing |

## Running it

1. Open `Clear Well.xcodeproj` in Xcode 27, pick an iPhone simulator or your iPhone, and press **⌘R**.
2. For AI explanations and photo scanning, start the server (see [server/README.md](server/README.md)) and enter its address in **Settings → AI server**.
3. To load sample data for a demo, open **Settings**, tap **Version** five times, then tap **Load demo data**.

Run the tests with **⌘U** in Xcode.

## Disclaimer

ClearWell is not a substitute for a certified lab or the Minnesota Department of Health. Status colors are based on published EPA and MDH guidance; check those sources for the latest limits.

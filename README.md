# ClearWell

**Turn a confusing well-water lab report into a clear next step.**

About a million Minnesotans drink from private wells, and no agency tests that water for them. When a lab report comes back, it is a page of chemical names and numbers. ClearWell turns it into plain English: what is safe, what is not, who in the household is most at risk, and exactly what to do next. It also helps every household — private well or city water — use less water, and shows how each home fits into the community's shared water.

Built for the Congressional App Challenge, Minnesota's 6th District.

## How it works

1. **Add results.** Photograph the lab report or type the numbers in. Every scanned number must be confirmed before it is saved.
2. **See what they mean.** Each contaminant gets a green, amber or red status, an explanation written for your household, and a "What to do next" step.
3. **Track and act.** History charts show whether water is getting worse, reminders follow the Minnesota Department of Health (MDH) testing schedule, and Get Help lists accredited labs and county contacts.
4. **Conserve.** Enter meter readings or water bills to compare days, weeks and months, set a goal, and get an alert when use jumps the way a leak would. Suggested savings are always labeled as estimates from EPA WaterSense figures; measured savings come only from your own readings.
5. **Community.** A Local Water dashboard explains drought, flood alerts and rain for your county (live from the U.S. Drought Monitor and National Weather Service), plus groundwater, lakes and local projects. Optional community challenges show anonymous totals, and the Action Center explains how to protect shared water and where to report concerns.

## The rule that makes it trustworthy

**Colors come only from a fixed table of official EPA and MDH limits** ([OfficialLimits.swift](Clear%20Well/Model/OfficialLimits.swift)), never from AI. The AI (Claude, by Anthropic) does three jobs only: reading numbers from a photo, which the user then confirms; explaining results in plain language; and suggesting ways to save water. It cannot change a color, diagnose anyone, or decide whether water is safe, and every red result points to MDH or a certified lab. Water-use math and leak alerts are plain calculations, and the AI can't invent savings numbers — it can only point to published EPA WaterSense figures.

## Privacy

Test results stay on the phone. A photo is sent for reading only when the user scans one, and explanations receive only the results and the household answers (water source, baby or pregnant person at home, well age, county). Water-use readings stay on the phone too; only a summary is sent for AI tips. Community challenges receive only a random ID and numbers, and show totals only once 5 households join. Local water updates ask public services (U.S. Drought Monitor, National Weather Service) about your county only. The Claude API key lives on a small server, never in the app.

## Project layout

| Folder | What's inside |
|---|---|
| `Clear Well/Model` | Official limits table, testing schedule, trend math, unit conversion, county resources, water-use math, local water and community content |
| `Clear Well/Views` | SwiftUI screens: Home, Water Quality, Results, Conserve, Community, Get Help, Settings |
| `Clear Well/AI` | Calls to the ClearWell server, plus on-phone fallback explanations |
| `ClearWellTests` | Unit tests for the limits, schedule, trends, conversions, water-use math and local water text |
| `server` | Small TypeScript server that calls Claude ([setup guide](server/README.md)) |
| `docs` | Planning documents and a sample lab report for testing |

## Running it

1. Open `Clear Well.xcodeproj` in Xcode 27, pick an iPhone simulator or your iPhone, and press **⌘R**.
2. For AI explanations and photo scanning, start the server (see [server/README.md](server/README.md)) and enter its address in **Settings → AI server**.
3. To load sample data for a demo, open **Settings**, tap **Version** five times, then tap **Load demo data**.

Run the tests with **⌘U** in Xcode.

## Disclaimer

ClearWell is not a substitute for a certified lab or the Minnesota Department of Health. Status colors are based on published EPA and MDH guidance; check those sources for the latest limits.

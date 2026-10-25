# VentureStorm

**Crash-test your business idea before you spend your money.**

VentureStorm is an iPhone app that lets students model their own small business, run it through 500 possible futures, find which guess matters most, and learn how to fix it. Built for the 2026 Congressional App Challenge.

**Demo video:** _add YouTube link here_

## The problem

Students who start a side business (merch, baking, tutoring, reselling) usually plan around one guess, like "I'll sell 50 a month." They don't know which guess matters most, so they test the wrong thing, or nothing, until money is already gone.

## What the app does

1. **Build** – describe the idea (AI can suggest starting numbers), then set price, cost per item, monthly costs, starting cash, customers (slow / normal / great month) and price sensitivity. Each step teaches a concept with your own numbers: margin, break-even, cash runway, risk, price elasticity.
2. **Predict** – guess the result before seeing it.
3. **Results** – typical profit, a chart of cash over time across the futures, how often you lose money or run out of cash, and the **biggest driver** of your result.
4. **Fix-It Coach** – finds the main problem, gives hints, then shows fixes that were already tested by the simulation, with before/after numbers.

Also: light and dark mode, text size, color-blind friendly colors, reduce motion, haptics and VoiceOver labels.

## How the simulation works

- **Monte Carlo simulation:** the business is run 500 times with different random luck, 12 months each.
- **Customers:** each future picks how good the year is between the slow and great guesses (usually near the normal guess), then each month moves up or down about 10%. A higher price loses some customers (price elasticity).
- **Each month:** `profit = customers × (price − cost per item) − monthly costs`, added to cash. A future "runs out of cash" if cash goes below $0.
- **Repeatable:** a seeded random number generator means the same seed always gives the same results.
- **Fair tests:** the random luck is created once and reused, so when one input changes, all 500 futures have the same luck. The biggest-driver ranking and every Fix-It fix use this.

## How AI is used

- AI (Groq API, `openai/gpt-oss-20b`) suggests starting numbers from a typed idea and rewrites Fix-It hints.
- The simulation does all the math. A number check rejects any AI text with a number the simulation did not calculate.
- Without a key or internet, the app uses built-in starter templates.

## Run it

1. Open `VentureStorm.xcodeproj` in Xcode (iOS 17+ target).
2. Optional AI: copy `Secrets.swift.example` to `VentureStorm/Secrets.swift` and paste a free key from console.groq.com. (`Secrets.swift` is in `.gitignore`.)
   Without a key, create the same file with an empty string, or paste a key in the app's Settings.
3. Pick an iPhone simulator and press Run.

## Code layout

| File | What it does |
|---|---|
| `Models.swift` | Inputs, seeded random numbers, lesson formulas |
| `Simulator.swift` | Runs the 500 futures |
| `Detective.swift` | Tests one input at a time to find the biggest driver |
| `FixItCoach.swift` | Finds the main problem and tests fixes |
| `AIService.swift`, `GroqAI.swift` | AI interface, offline templates, number check |
| `*View.swift` | The screens |

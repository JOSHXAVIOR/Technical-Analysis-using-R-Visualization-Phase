# BDA400 Assignment 6 — Technical Analysis using R, Visualization Phase
**Student:** Joseph Anil Tenneti

## Run
1. Install R and RStudio. Open this folder as the working directory.
2. Run `source("install_packages.R")` once.
3. Run `shiny::runApp(".")`.
4. Enter a Yahoo Finance ticker, date range and time frame. Click Fetch / refresh data.
5. Change charts, indicators, SMA periods, trading rules and RSI thresholds interactively.
6. Click Fetch again after changing the symbol or date range. Charts always show the last fetched selection until refreshed.

## Requirements covered
- Step 1: Yahoo Finance through quantmod, dependencies and download error handling.
- Step 2: Shiny UI/server, date range, symbol, Daily/Weekly/Monthly OHLC aggregation, Line/Candlestick/Area charts.
- Step 3: configurable SMA and RSI; MACD 12/26/9; independent indicator toggles. SMA overlays price; RSI and MACD are aligned panels because their units differ from price.
- Step 4: actual SMA or MACD crossing events, plus RSI recovery/reversal crossings; clear Buy/Sell markers; Hold shown in the data table and CSV.

A Buy occurs when the short SMA crosses from below to above the long SMA. A Sell occurs for the reverse crossing. Equal values preserve the previous nonzero direction. Hold denotes no new event. MACD uses the same crossing logic versus its signal line. RSI Buy occurs on an upward exit from oversold; Sell occurs on a downward exit from overbought. Signals are bar-close observations, not trades or a backtest.

Warm-up data are fetched before the selected start date so indicators are computed before display filtering. Indicators use bars of the chosen time frame, so SMA 20 means 20 weekly bars in Weekly mode. Missing OHLC rows are removed and counted; insufficient history produces a readable error. Unfinished weekly/monthly terminal bars are omitted conservatively. This can omit a completed holiday-shortened weekly bar. Daily data may include today's unfinished bar; choose an earlier end date for completed daily observations.

The application uses unadjusted OHLC. Splits and dividends can affect indicators. This is the assignment's single-symbol portfolio analysis dashboard; it does not calculate holdings, account value, profit, or transaction costs. Yahoo is the required source; no second live provider is claimed. Separate indicator panels replace the illustrative geom_ma/geom_rsi/geom_macd placeholders in the assignment, which are not standard ggplot2 functions.

## Verification status
R/Rscript is unavailable in the authoring environment. The application was reviewed statically but has NOT been executed with R or tested against a live Yahoo download. No execution screenshots or observed trading results are claimed.

Before submission, run the app and check:
- AAPL over a multi-year range loads; recent table and CSV match.
- Daily, Weekly and Monthly change OHLC aggregation and indicator periods.
- All three chart types display; toggle each indicator off/on.
- SMA crossings annotate only changes of direction, not every bullish/bearish bar.
- Try MACD and RSI rules and change SMA/RSI parameters.
- An invalid ticker, reversed date range, future end and short >= long give useful errors.
- A weekend-only range or too-short/new-listing history gives a readable message.

## GitHub and LMS — required final steps
1. Create a public GitHub repository (suggested name: JosephAnilTenneti_BDA400_A06).
2. Upload app.R, install_packages.R, README.md and the cover page. Commit changes.
3. Replace the repository-link placeholder in CoverPage.docx with the real public URL and export to PDF, replacing CoverPage.pdf.
4. Check the repository opens when signed out. Submit the updated cover page and repository link to the LMS.


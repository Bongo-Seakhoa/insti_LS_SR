# Liquidity-Sweep S/R Institutional EA

## Table of Contents
1. [Overview](#overview)
2. [Strategy Foundations](#strategy-foundations)
3. [Core Components](#core-components)
4. [Installation](#installation)
5. [Parameters](#parameters)
6. [Trading Logic](#trading-logic)
7. [Position Management](#position-management)
8. [Risk Management](#risk-management)
9. [Performance Expectations](#performance-expectations)
10. [Troubleshooting](#troubleshooting)
11. [Customization](#customization)

## Overview

The Liquidity-Sweep S/R Institutional EA is a sophisticated algorithmic trading system designed to exploit institutional trading behaviors around key support and resistance zones in forex markets. The strategy focuses on identifying liquidity sweeps (stop hunts) and break-and-retest patterns that frequently occur at significant price levels where large order clusters exist.

**Key Features:**
- Automated detection of high-probability support/resistance zones
- Exploitation of liquidity sweeps/stop hunts
- Break-and-retest continuation strategy
- Adaptive position sizing and dynamic risk control
- Professional trailing stop mechanisms
- Multi-timeframe analysis (Daily/Weekly scanning, H4/H1 execution)

**Target Markets:** Major forex pairs (EURUSD, GBPUSD, USDJPY, etc.)

## Strategy Foundations

The EA is built on the hypothesis that price action is nearly random except at long-established support & resistance zones where large resting orders typically exist. It specifically targets two high-probability patterns:

1. **Liquidity-Sweep Fade**: When institutional players hunt retail stops beyond obvious levels, then reverse price action to the zone
   
2. **Break-and-Retest Continuation**: When a significant level finally breaks, the first price pullback provides asymmetric risk/reward opportunity

This edge is supported by market microstructure principles, where institutions often need to build positions by creating liquidity via stop hunting before initiating their intended directional move.

## Core Components

The EA consists of five interconnected modules:

1. **Zone Detector (ZoneDetector.mqh)**
   - Identifies and scores S/R zones based on historical price action
   - Tracks zone status, strength, and interaction history
   - Implements fractal pivot detection and clustering

2. **Macro Filter (MacroFilter.mqh)**
   - Filters trades based on USD Index trend and volatility metrics
   - Ensures alignment with broader market conditions
   - Reduces false signals during unfavorable conditions

3. **Risk Engine (RiskEngine.mqh)**
   - Controls position sizing based on account risk parameters
   - Implements correlation management between open positions
   - Manages drawdown and risk limitations

4. **Position Manager (PosManager.mqh)**
   - Handles dynamic position management
   - Implements pyramiding on successful trades
   - Manages trailing stops using Chandelier and Anchored VWAP methodologies

5. **Main EA (Insti_LS_SR.mq5)**
   - Orchestrates overall strategy execution
   - Manages trade entry timing and execution
   - Implements sweep detection and break-retest logic

## Installation

1. **Files Required**:
   - `Insti_LS_SR.mq5` (Main EA file)
   - `Common.mqh` (Shared definitions)
   - `ZoneDetector.mqh` (Zone detection logic)
   - `MacroFilter.mqh` (Macro filtering)
   - `RiskEngine.mqh` (Risk management)
   - `PosManager.mqh` (Position management)

2. **Installation Steps**:
   - Copy all files to your MetaTrader 5 `Experts` folder
   - Restart MetaTrader 5 or refresh the Navigator panel
   - Verify the EA appears in your Navigator under Expert Advisors

3. **Requirements**:
   - MetaTrader 5 (build 4150 or higher)
   - Broker with reliable execution and reasonable spreads
   - Access to USD Index (USDX) if using the macro filter

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| **BaseRiskPct** | 0.5 | Base risk percentage per trade (risk per trade as % of account balance) |
| **PyramidAdds** | 3 | Maximum number of additional positions to add on winning trades |
| **ZoneDepthATR** | 0.5 | Zone depth as multiplier of ATR (defines the width of S/R zones) |
| **MacroFilterON** | true | Enable/disable the macro market filter (DXY trend and volatility) |
| **Magic** | 12345 | Unique magic number for trade identification |

**Advanced Parameters (previously available):**
- **MaxDD**: Maximum allowed drawdown percentage (removed in latest version)
- **Drawdown ladder**: Risk scaling based on account drawdown (0-5% DD → full risk; 5-10% → half risk; ≥10% → no risk until recovery)
- **VaR throttle**: Value-at-Risk based position limits

## Trading Logic

### Zone Detection
- 3-bar fractal pivots are detected on D1 timeframe
- Pivots are clustered within 0.5 × ATR(D1) to identify zones
- Zones are scored based on: (sweeps² × ln(age))
- Top 8 zones per symbol are tracked and monitored

### Liquidity-Sweep Fade Entry
1. Price extends ≥0.25 × ATR(H4) beyond zone and closes back inside
2. H1 timeframe confirms with higher-low (long) or lower-high (short)
3. Entry occurs at market on the next available price
4. Stop loss placed beyond zone edge + ATR buffer
5. Cooldown period prevents multiple entries on the same zone

### Break-and-Retest Entry
1. H4 close occurs ≥0.5 × ATR beyond zone
2. Price returns to retest the zone within 12 H4 bars
3. H1 timeframe confirms with inside-bar pattern at zone
4. Limit order placed at zone edge
5. Stop loss placed beyond opposite zone edge + ATR buffer

### Entry Filters
- DXY 20-EMA slope must favor trade direction
- 1-week realized volatility must be below 60-day median
- Correlation with existing positions limited to manage risk
- Cooldown periods to prevent overtrading

## Position Management

### Scaling In (Pyramiding)
- Initial position risks 0.5% of equity
- Up to 3 additional positions can be added on profitable trades
- Each add-on risks 0.3% of equity and is funded by open profit
- Each pyramid level updates stops for all positions in that direction

### Exit Management
- 25% partial profit at +2R (if ≥2 pyramids added)
- Trailing stop using Chandelier method: HighestClose – 3 × ATR(H4)
- Anchored VWAP from trade entry also used as trailing reference
- Time stop closes trades at breakeven if <+1R after 6 H4 bars

## Risk Management

The EA implements multiple layers of risk control:

### Position Sizing
- Base risk of 0.5% per trade calculated dynamically based on stop distance
- Position size normalized to broker's lot step requirements
- Minimum/maximum lot size constraints enforced

### Risk Constraints (Optional)
- **MaxDD**: Disables trading if account drawdown exceeds threshold
- **Drawdown ladder**: Scales risk based on current drawdown level
- **VaR throttle**: Limits exposure based on 95% 1-day historical VaR budget

### Correlation Management
- Positions with correlation >75% have combined risk capped to 1R
- Positions with opposite direction reduce overall portfolio risk

### Daily Risk Limits
- Trading disabled after -2R closed P/L in UTC day
- Counter resets daily to allow fresh trading opportunities

## Performance Expectations

Based on the strategy design, the EA targets:

- **Profit Factor**: ≥1.35
- **Sharpe Ratio**: ≥1.3
- **Drawdown**: ≤15% peak-to-valley equity
- **Win Rate**: 45-55% (strategy relies on favorable R:R rather than high win rate)
- **Average Winner**: 2-3× average loser

The strategy is designed for consistency rather than extraordinary gains, focusing on capturing predictable institutional behavior at key levels.

## Troubleshooting

### Common Issues

1. **"Invalid stops" errors**
   - Ensure your broker's minimum stop distance is respected
   - Consider increasing the safety buffer in TrailPosition function
   - Check if your broker has unusual stop level requirements

2. **Multiple entries on same zone**
   - Verify zone cooldown period is sufficient
   - Check if zone detection is creating duplicate zones
   - Ensure proper zone tracking with lastTradeTime field

3. **Risk lockup ("VaR risk budget exceeded")**
   - May occur if position tracking gets out of sync
   - Restart the EA to reset risk tracking
   - Consider modifying RiskEngine for your risk tolerance

4. **Break detection flooding**
   - Adjust break detection thresholds
   - Increase cooldown periods between break detections
   - Ensure proper zone scoring to prioritize most significant levels

### Performance Optimization

- **Parameter Optimization Range**:
  - ZoneDepthATR: 0.3-0.6
  - BaseRiskPct: 0.4-1.0
  - PyramidAdds: 2-4

- **Testing Protocol**:
  - Back-test with tick data and slippage
  - Walk-forward test with 1-year optimization periods
  - Monte Carlo simulations to verify robustness

## Customization

### Adaptations for Different Markets
- **Cryptocurrency**: Consider wider zone definitions (higher ZoneDepthATR)
- **Indices**: Adjust macro filter to align with market-specific correlations
- **Low volatility pairs**: Reduce minimum movement thresholds

### Code Modification Points
- `ZoneDetector.mqh`: Customize zone scoring algorithm
- `MacroFilter.mqh`: Change correlation filters for specific instruments
- `PosManager.mqh`: Modify trailing stop methodology
- `RiskEngine.mqh`: Adjust risk parameters for your trading style

### Advanced Extensions
- **Order Flow Integration**: Add order flow confirmation to entries
- **Time Filters**: Add session-based filters (London, NY, Tokyo)
- **Machine Learning**: Add classification of zone quality based on historical performance
- **Alternative Data**: Integrate COT data or sentiment indicators for enhanced filtering

---

## Disclaimer

This EA is designed for experienced traders who understand algorithmic trading principles and risk management. Past performance is not indicative of future results. Always test thoroughly on demo accounts before live deployment. The strategy parameters should be adapted to your specific risk tolerance and trading objectives.

---

*© Bongo Seakhoa - Liquidity-Sweep S/R Institutional EA*

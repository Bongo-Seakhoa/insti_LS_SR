//+------------------------------------------------------------------+
//|                                            Insti_LS_SR.mq5       |
//|                                               Bongo Seakhoa       |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""
#property version   "1.00"
#property strict

// When compiling, make sure all .mqh files are in the same folder as this .mq5 file
// Or use absolute paths if needed:
// #include "C:\\Path\\To\\Your\\Common.mqh"

// Include necessary header files
#include <Trade\Trade.mqh>
#include "Common.mqh"
#include "ZoneDetector.mqh"
#include "MacroFilter.mqh"
#include "RiskEngine.mqh"
#include "PosManager.mqh"

// Input parameters
input double BaseRiskPct = 0.5;         // Base risk percentage per trade
input double MaxDD = 50.0;              // Maximum allowed drawdown percentage
input int PyramidAdds = 3;              // Maximum additional pyramid positions
input double ZoneDepthATR = 0.5;        // Zone depth as multiplier of ATR
input bool MacroFilterON = true;        // Enable/disable macro filter
input int Magic = 12345;                // Magic number for trade identification

// Global variables
CTrade Trade;                         // Trading object
CZoneDetector ZoneDetector;           // Zone detection object
CMacroFilter MacroFilter;             // Macro filter object
CRiskEngine RiskEngine;               // Risk management object
CPosManager PosManager;               // Position management object

// Handles for indicators
int ATRHandleD1 = INVALID_HANDLE;     // Daily ATR handle
int ATRHandleH4 = INVALID_HANDLE;     // 4-hour ATR handle
int ATRHandleH1 = INVALID_HANDLE;     // 1-hour ATR handle
int EMAHandle = INVALID_HANDLE;       // EMA handle for DXY

// Timers and state variables
datetime lastScanTime = 0;            // Last time zones were scanned
datetime lastTradeCheckTime = 0;      // Last time trade conditions were checked
bool isInitialized = false;           // Flag to track initialization status
int chartInstance = 0;                // Chart instance ID to prevent duplicates

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Set the magic number for trade identification
    Trade.SetExpertMagicNumber(Magic);
    
    // Initialize indicator handles
    ATRHandleD1 = iATR(_Symbol, PERIOD_D1, 14);
    ATRHandleH4 = iATR(_Symbol, PERIOD_H4, 14);
    ATRHandleH1 = iATR(_Symbol, PERIOD_H1, 14);
    
    // Check if indicator handles are valid
    if(ATRHandleD1 == INVALID_HANDLE || ATRHandleH4 == INVALID_HANDLE || ATRHandleH1 == INVALID_HANDLE)
    {
        Print("Failed to create ATR indicators. Error code: ", GetLastError());
        return INIT_FAILED;
    }
    
    // Initialize the DXY EMA handle if macro filter is enabled
    if(MacroFilterON)
    {
        // Use USD index for macro filter if available
        EMAHandle = iMA("USDX", PERIOD_D1, 20, 0, MODE_EMA, PRICE_CLOSE);
        if(EMAHandle == INVALID_HANDLE)
        {
            Print("Warning: Failed to create EMA indicator for DXY. Macro filter may not work properly.");
        }
    }
    
    // Initialize the objects
    bool initZoneDetector = ZoneDetector.Init(_Symbol, ZoneDepthATR, ATRHandleD1);
    bool initMacroFilter = MacroFilter.Init(EMAHandle, MacroFilterON);
    bool initRiskEngine = RiskEngine.Init(BaseRiskPct, MaxDD);
    bool initPosManager = PosManager.Init(_Symbol, ATRHandleH4, ATRHandleH1, PyramidAdds);
    
    if(!initZoneDetector || !initMacroFilter || !initRiskEngine || !initPosManager)
    {
        Print("Failed to initialize one or more components. Error code: ", GetLastError());
        return INIT_FAILED;
    }
    
    // Ensure we're not running duplicate instances on the same chart
    chartInstance = (int)ChartID();
    
    // Set up timer for regular checks (hourly)
    EventSetTimer(3600);
    
    // Flag initialization as successful
    isInitialized = true;
    
    // Perform initial zone scan
    ScanZones();
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Release indicator handles
    if(ATRHandleD1 != INVALID_HANDLE) IndicatorRelease(ATRHandleD1);
    if(ATRHandleH4 != INVALID_HANDLE) IndicatorRelease(ATRHandleH4);
    if(ATRHandleH1 != INVALID_HANDLE) IndicatorRelease(ATRHandleH1);
    if(EMAHandle != INVALID_HANDLE) IndicatorRelease(EMAHandle);
    
    // Kill timer
    EventKillTimer();
    
    // Clean up and log the reason for deinitialization
    Print("EA Deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(!isInitialized) return;
    
    // Check if it's time to scan for new zones (daily)
    datetime currentTime = TimeCurrent();
    if(currentTime - lastScanTime >= PeriodSeconds(PERIOD_D1))
    {
        ScanZones();
        lastScanTime = currentTime;
    }
    
    // Check trade conditions on each new H1 candle
    datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
    if(currentBarTime != lastTradeCheckTime)
    {
        // Check and manage existing positions first
        PosManager.ManagePositions(Trade);
        
        // Check if we're allowed to open new trades
        if(RiskEngine.CanOpenNewTrades())
        {
            // Check for liquidity sweep triggers
            CheckLiquiditySweepTriggers();
            
            // Check for break and retest opportunities
            CheckBreakAndRetestOpportunities();
        }
        
        lastTradeCheckTime = currentBarTime;
    }
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Update risk management based on current account state
    RiskEngine.UpdateRiskStatus();
    
    // Check and manage existing positions
    PosManager.ManagePositions(Trade);
}

//+------------------------------------------------------------------+
//| Scan for Support and Resistance zones                            |
//+------------------------------------------------------------------+
void ScanZones()
{
    // Detect and score zones on daily/weekly charts
    ZoneDetector.DetectZones();
    
    // Log the scan completion and number of zones found
    Print("Zone scan completed. Found ", ZoneDetector.GetZoneCount(), " qualified zones.");
}

//+------------------------------------------------------------------+
//| Check for liquidity sweep triggers at key zones                  |
//+------------------------------------------------------------------+
void CheckLiquiditySweepTriggers()
{
    // Get current 4-hour ATR value
    double atrH4 = GetATRValue(ATRHandleH4, 0);
    if(atrH4 <= 0) return;
    
    // Get current price
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Check each zone for a liquidity sweep
    int zoneCount = ZoneDetector.GetZoneCount();
    for(int i = 0; i < zoneCount; i++)
    {
        SZone zone;
        if(!ZoneDetector.GetZone(i, zone)) continue;
        
        // Check if price extended beyond zone and closed back inside (liquidity sweep)
        bool sweepDetected = false;
        ENUM_TRADE_DIRECTION direction = TRADE_DIRECTION_NONE;
        
        // Calculate zone boundaries
        double upperBound = zone.midPrice + zone.width/2;
        double lowerBound = zone.midPrice - zone.width/2;
        
        // Get previous and current 4-hour candle data
        double previousHigh = iHigh(_Symbol, PERIOD_H4, 1);
        double previousLow = iLow(_Symbol, PERIOD_H4, 1);
        double previousClose = iClose(_Symbol, PERIOD_H4, 1);
        
        // Check for sweep above resistance
        if(previousHigh > upperBound + 0.25 * atrH4 && previousClose < upperBound)
        {
            sweepDetected = true;
            direction = TRADE_DIRECTION_SHORT;
        }
        // Check for sweep below support
        else if(previousLow < lowerBound - 0.25 * atrH4 && previousClose > lowerBound)
        {
            sweepDetected = true;
            direction = TRADE_DIRECTION_LONG;
        }
        
        // If we detected a sweep, mark the zone as having a pending fade
        if(sweepDetected)
        {
            zone.pendingFade = true;
            zone.fadeDirection = direction;
            ZoneDetector.UpdateZone(i, zone);
            
            Print("Liquidity sweep detected at zone ", i, ". Direction: ", 
                  (direction == TRADE_DIRECTION_LONG ? "LONG" : "SHORT"));
            
            // Check for fade entry conditions in H1 timeframe
            CheckFadeEntrySetup(zone, direction);
        }
    }
}

//+------------------------------------------------------------------+
//| Check for fade entry setup on H1 timeframe                       |
//+------------------------------------------------------------------+
// In CheckFadeEntrySetup function:
void CheckFadeEntrySetup(SZone &zone, ENUM_TRADE_DIRECTION direction)
{
    // Check if the macro filter allows this direction
    if(MacroFilterON && !MacroFilter.CheckFilter(direction))
    {
        Print("Macro filter rejected trade direction: ", 
              (direction == TRADE_DIRECTION_LONG ? "LONG" : "SHORT"));
        return;
    }
    
    // Get H1 candle data
    double h1High = iHigh(_Symbol, PERIOD_H1, 1);
    double h1Low = iLow(_Symbol, PERIOD_H1, 1);
    double h1Close = iClose(_Symbol, PERIOD_H1, 1);
    double prevH1High = iHigh(_Symbol, PERIOD_H1, 2);
    double prevH1Low = iLow(_Symbol, PERIOD_H1, 2);
    
    bool validFadeSetup = false;
    
    // Check for a higher-low in long setup
    if(direction == TRADE_DIRECTION_LONG && h1Low > prevH1Low)
    {
        validFadeSetup = true;
    }
    // Check for a lower-high in short setup
    else if(direction == TRADE_DIRECTION_SHORT && h1High < prevH1High)
    {
        validFadeSetup = true;
    }
    
    // If we have a valid fade setup, execute the entry
    if(validFadeSetup)
    {
        // Calculate stop loss level based on zone edge
        double stopLoss = 0.0;
        double atrH4 = GetATRValue(ATRHandleH4, 0);
        
        if(direction == TRADE_DIRECTION_LONG)
        {
            stopLoss = zone.midPrice - zone.width/2 - atrH4;
        }
        else if(direction == TRADE_DIRECTION_SHORT)
        {
            stopLoss = zone.midPrice + zone.width/2 + atrH4;
        }
        
        // Calculate position size based on risk
        double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (BaseRiskPct / 100.0);
        double entryPrice = SymbolInfoDouble(_Symbol, (direction == TRADE_DIRECTION_LONG) ? SYMBOL_ASK : SYMBOL_BID);
        double stopDistance = MathAbs(entryPrice - stopLoss);
        
        // Execute the fade entry
        if(ExecuteTradeWithRisk(direction, riskAmount, stopLoss, "Fade"))
        {
            Print("Executed fade entry at zone ", zone.midPrice, ". Direction: ", 
                  (direction == TRADE_DIRECTION_LONG ? "LONG" : "SHORT"));
            
            // Reset the pending fade flag
            zone.pendingFade = false;
            
            // Update the zone in the detector
            int zoneCount = ZoneDetector.GetZoneCount();
            for(int idx = 0; idx < zoneCount; idx++)
            {
                SZone tempZone;
                if(ZoneDetector.GetZone(idx, tempZone))
                {
                    // Check if this is our zone (matching by midPrice which should be unique)
                    if(MathAbs(tempZone.midPrice - zone.midPrice) < 0.0000001)
                    {
                        ZoneDetector.UpdateZone(idx, zone);
                        break;
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for break and retest opportunities                         |
//+------------------------------------------------------------------+
void CheckBreakAndRetestOpportunities()
{
    // Static variables to limit break detections
    static datetime lastBreakCheckTime = 0;
    static int breakDetectionCount = 0;
    
    // Reset counter each hour
    datetime currentTime = TimeCurrent();
    if(currentTime - lastBreakCheckTime > PeriodSeconds(PERIOD_H1))
    {
        breakDetectionCount = 0;
        lastBreakCheckTime = currentTime;
    }
    
    // Limit number of break detections per hour
    if(breakDetectionCount >= 2)
    {
        return;
    }
    
    // Get current 4-hour ATR value
    double atrH4 = GetATRValue(ATRHandleH4, 0);
    if(atrH4 <= 0) return;
    
    // Get current price and 4-hour close
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double h4Close = iClose(_Symbol, PERIOD_H4, 1);
    
    // Count of breaks detected in this check
    int breaksDetected = 0;
    
    // Check each zone for a break and potential retest
    int zoneCount = ZoneDetector.GetZoneCount();
    for(int i = 0; i < zoneCount; i++)
    {
        // Limit total breaks detected per check
        if(breaksDetected >= 2) break;
        
        SZone zone;
        if(!ZoneDetector.GetZone(i, zone)) continue;
        
        // Skip zones with pending fades
        if(zone.pendingFade) continue;
        
        // Skip zones that were recently traded
        //if(TimeCurrent() - zone.lastTradeTime < PeriodSeconds(PERIOD_H4) * 4) continue;
        
        // Calculate zone boundaries
        double upperBound = zone.midPrice + zone.width/2;
        double lowerBound = zone.midPrice - zone.width/2;
        
        // Check for a break (4-hour close beyond the zone)
        ENUM_TRADE_DIRECTION breakDirection = TRADE_DIRECTION_NONE;
        
        // Only check for breaks if we haven't detected a break recently on this zone
        // or if the detected break direction is different
        if(TimeCurrent() - zone.breakTime > PeriodSeconds(PERIOD_D1)) // Only check once per day
        {
            if(h4Close > upperBound + 0.5 * atrH4 && zone.breakDirection != TRADE_DIRECTION_LONG)
            {
                breakDirection = TRADE_DIRECTION_LONG;
                breaksDetected++;
            }
            else if(h4Close < lowerBound - 0.5 * atrH4 && zone.breakDirection != TRADE_DIRECTION_SHORT)
            {
                breakDirection = TRADE_DIRECTION_SHORT;
                breaksDetected++;
            }
        }
        
        // If we detected a break, look for a retest
        if(breakDirection != TRADE_DIRECTION_NONE)
        {
            zone.breakDirection = breakDirection;
            zone.breakTime = TimeCurrent();
            ZoneDetector.UpdateZone(i, zone);
            
            Print("Break detected at zone ", i, ". Direction: ", 
                  (breakDirection == TRADE_DIRECTION_LONG ? "LONG" : "SHORT"));
                  
            // Count this in our hourly break detection total
            breakDetectionCount++;
        }
        
        // Check for retest opportunity if the zone was broken within the past 12 H4 bars
        if(zone.breakDirection != TRADE_DIRECTION_NONE && 
           TimeCurrent() - zone.breakTime < 12 * PeriodSeconds(PERIOD_H4))
        {
            // Check for a retest (price comes back to the zone level)
            bool retestDetected = false;
            
            if(zone.breakDirection == TRADE_DIRECTION_LONG && 
               currentPrice <= upperBound && currentPrice > lowerBound)
            {
                retestDetected = true;
            }
            else if(zone.breakDirection == TRADE_DIRECTION_SHORT && 
                    currentPrice >= lowerBound && currentPrice < upperBound)
            {
                retestDetected = true;
            }
            
            // If we found a retest, check for inside-bar stall
            if(retestDetected)
            {
                // Check for inside bar on H1
                double h1High = iHigh(_Symbol, PERIOD_H1, 1);
                double h1Low = iLow(_Symbol, PERIOD_H1, 1);
                double prevH1High = iHigh(_Symbol, PERIOD_H1, 2);
                double prevH1Low = iLow(_Symbol, PERIOD_H1, 2);
                
                bool insideBar = (h1High <= prevH1High && h1Low >= prevH1Low);
                
                if(insideBar)
                {
                    // Check macro filter
                    if(MacroFilterON && !MacroFilter.CheckFilter(zone.breakDirection))
                    {
                        Print("Macro filter rejected break-retest. Direction: ", 
                              (zone.breakDirection == TRADE_DIRECTION_LONG ? "LONG" : "SHORT"));
                        continue;
                    }
                    
                    // Set up a limit order at the zone edge
                    double limitPrice = 0.0;
                    double stopLoss = 0.0;
                    
                    if(zone.breakDirection == TRADE_DIRECTION_LONG)
                    {
                        limitPrice = upperBound;
                        stopLoss = lowerBound - atrH4;
                    }
                    else if(zone.breakDirection == TRADE_DIRECTION_SHORT)
                    {
                        limitPrice = lowerBound;
                        stopLoss = upperBound + atrH4;
                    }
                    
                    // Check minimum stop distance
                    double minStopDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * 
                                           SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                    
                    // Ensure stop respects minimum distance
                    if(MathAbs(limitPrice - stopLoss) < minStopDistance)
                    {
                        // Adjust the stop to respect minimum distance
                        if(zone.breakDirection == TRADE_DIRECTION_LONG)
                            stopLoss = limitPrice - minStopDistance - 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT); // Extra buffer
                        else
                            stopLoss = limitPrice + minStopDistance + 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT); // Extra buffer
                    }
                    
                    // Calculate position size based on risk
                    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (BaseRiskPct / 100.0);
                    double stopDistance = MathAbs(limitPrice - stopLoss);
                    
                    // Place limit order for break-retest
                    if(PlaceLimitOrderWithRisk(zone.breakDirection, limitPrice, riskAmount, stopLoss, "BreakRetest"))
                    {
                        Print("Placed limit order for break-retest at zone ", zone.midPrice, ". Direction: ", 
                              (zone.breakDirection == TRADE_DIRECTION_LONG ? "LONG" : "SHORT"));
                        
                        // Mark the zone as processed for break-retest and update last trade time
                        zone.breakTime = 0; // Reset to prevent duplicate entries
                        //zone.lastTradeTime = TimeCurrent();
                        ZoneDetector.UpdateZone(i, zone);
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Execute a market trade with risk-based position sizing           |
//+------------------------------------------------------------------+
bool ExecuteTradeWithRisk(ENUM_TRADE_DIRECTION direction, double riskAmount, double stopLoss, string tradeType)
{
    // Check risk engine status first
    if(!RiskEngine.CanOpenNewTrades())
    {
        Print("Risk management prevented new trade execution");
        return false;
    }
    
    // Calculate entry price and stop distance
    double entryPrice = SymbolInfoDouble(_Symbol, (direction == TRADE_DIRECTION_LONG) ? SYMBOL_ASK : SYMBOL_BID);
    double stopDistance = MathAbs(entryPrice - stopLoss);
    
    if(stopDistance <= 0)
    {
        Print("Invalid stop distance for trade execution");
        return false;
    }
    
    // Calculate lot size based on risk
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    double ticksInStopDistance = stopDistance / tickSize;
    double lotSize = riskAmount / (ticksInStopDistance * tickValue);
    
    // Normalize lot size according to broker specifications
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    // Double-check if the stop level is valid (outside broker's freeze level)
    double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * 
                         SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    if(stopDistance < freezeLevel)
    {
        Print("Stop distance is too close (within freeze level): ", stopDistance, " vs ", freezeLevel);
        
        // Adjust the stop to respect freeze level
        if(direction == TRADE_DIRECTION_LONG)
            stopLoss = entryPrice - freezeLevel - 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT); // Extra buffer
        else
            stopLoss = entryPrice + freezeLevel + 5 * SymbolInfoDouble(_Symbol, SYMBOL_POINT); // Extra buffer
            
        // Recalculate stopDistance for position sizing
        stopDistance = MathAbs(entryPrice - stopLoss);
        ticksInStopDistance = stopDistance / tickSize;
        lotSize = riskAmount / (ticksInStopDistance * tickValue);
        
        // Normalize lot size again
        lotSize = MathFloor(lotSize / lotStep) * lotStep;
        lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    }
    
    // Check correlation risk with existing positions
    if(!RiskEngine.CheckCorrelationRisk(direction, lotSize))
    {
        Print("Correlation risk limit exceeded, reducing position size");
        lotSize = lotSize * 0.5; // Reduce position size
    }
    
    // Execute the trade
    bool result = false;
    if(direction == TRADE_DIRECTION_LONG)
    {
        result = Trade.Buy(lotSize, _Symbol, 0, stopLoss, 0, tradeType);
    }
    else
    {
        result = Trade.Sell(lotSize, _Symbol, 0, stopLoss, 0, tradeType);
    }
    
    // Register the trade with the position manager if successful
    if(result)
    {
        ulong ticket = Trade.ResultOrder();
        PosManager.RegisterNewPosition(ticket, direction, entryPrice, stopLoss, lotSize, tradeType);
        
        // Register the trade with risk engine
        RiskEngine.RegisterNewTrade(direction, lotSize, stopDistance);
        
        return true;
    }
    else
    {
        Print("Trade execution failed. Error: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Place a limit order with risk-based position sizing              |
//+------------------------------------------------------------------+
bool PlaceLimitOrderWithRisk(ENUM_TRADE_DIRECTION direction, double limitPrice, double riskAmount, double stopLoss, string tradeType)
{
    // Check risk engine status first
    if(!RiskEngine.CanOpenNewTrades())
    {
        Print("Risk management prevented new limit order placement");
        return false;
    }
    
    // Calculate stop distance
    double stopDistance = MathAbs(limitPrice - stopLoss);
    
    if(stopDistance <= 0)
    {
        Print("Invalid stop distance for limit order");
        return false;
    }
    
    // Calculate lot size based on risk
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    
    double ticksInStopDistance = stopDistance / tickSize;
    double lotSize = riskAmount / (ticksInStopDistance * tickValue);
    
    // Normalize lot size according to broker specifications
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
    
    // Double-check if the stop level is valid (outside broker's freeze level)
    double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * 
                         SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double minStopDistance = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * 
                             SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    // Use the larger of freeze level and minimum stop distance
    double requiredDistance = MathMax(freezeLevel, minStopDistance);
    
    if(stopDistance < requiredDistance)
    {
        Print("Stop distance is too close (within required distance): ", stopDistance, " vs ", requiredDistance);
        
        // Adjust the stop to respect required distance
        if(direction == TRADE_DIRECTION_LONG)
            stopLoss = limitPrice - requiredDistance - 10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT); // Extra buffer
        else
            stopLoss = limitPrice + requiredDistance + 10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT); // Extra buffer
            
        // Recalculate stopDistance for position sizing
        stopDistance = MathAbs(limitPrice - stopLoss);
        ticksInStopDistance = stopDistance / tickSize;
        lotSize = riskAmount / (ticksInStopDistance * tickValue);
        
        // Normalize lot size again
        lotSize = MathFloor(lotSize / lotStep) * lotStep;
        lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
        
        Print("Adjusted stop to: ", stopLoss, " with new distance: ", stopDistance);
    }
    
    // Check correlation risk with existing positions
    if(!RiskEngine.CheckCorrelationRisk(direction, lotSize))
    {
        Print("Correlation risk limit exceeded, reducing position size");
        lotSize = lotSize * 0.5; // Reduce position size
    }
    
    // Place the limit order
    bool result = false;
    if(direction == TRADE_DIRECTION_LONG)
    {
        result = Trade.BuyLimit(lotSize, limitPrice, _Symbol, stopLoss, 0, ORDER_TIME_GTC, 0, tradeType);
    }
    else
    {
        result = Trade.SellLimit(lotSize, limitPrice, _Symbol, stopLoss, 0, ORDER_TIME_GTC, 0, tradeType);
    }
    
    // Register the pending order with the position manager if successful
    if(result)
    {
        ulong ticket = Trade.ResultOrder();
        Print("Placed limit order #", ticket, " at ", limitPrice, " with stop at ", stopLoss);
        
        // Register the potential trade with risk engine
        RiskEngine.RegisterPendingOrder(direction, lotSize, stopDistance);
        
        return true;
    }
    else
    {
        Print("Limit order placement failed. Error: ", GetLastError());
        return false;
    }
}

//+------------------------------------------------------------------+
//| Get ATR value from indicator handle                              |
//+------------------------------------------------------------------+
double GetATRValue(int handle, int shift)
{
    double atrBuffer[];
    if(CopyBuffer(handle, 0, shift, 1, atrBuffer) <= 0)
    {
        Print("Failed to get ATR value. Error: ", GetLastError());
        return 0;
    }
    
    return atrBuffer[0];
}
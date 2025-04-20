//+------------------------------------------------------------------+
//|                                                PosManager.mqh     |
//|                                               Bongo Seakhoa       |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""

#include <Arrays\ArrayObj.mqh>
#include <Trade\Trade.mqh> // Add Trade.mqh for CTrade
#include "Common.mqh"     // Include Common.mqh for ENUM_TRADE_DIRECTION

// Position class that inherits from CObject for storage in CArrayObj
class CPosition : public CObject
{
public:
    ulong ticket;                   // Position ticket
    ENUM_TRADE_DIRECTION direction; // Trade direction
    double entryPrice;              // Entry price
    double stopLoss;                // Stop loss level
    double lotSize;                 // Position size
    string tradeType;               // Type of trade (Fade, BreakRetest)
    datetime openTime;              // Open time
    double initialR;                // Initial risk in account currency
    int pyramidCount;               // Number of pyramid additions
    double profits;                 // Current profit in account currency
    
    CPosition()
    {
        ticket = 0;
        direction = TRADE_DIRECTION_NONE;
        entryPrice = 0;
        stopLoss = 0;
        lotSize = 0;
        tradeType = "";
        openTime = 0;
        initialR = 0;
        pyramidCount = 0;
        profits = 0;
    }
};

// Class for position management
class CPosManager
{
private:
    CArrayObj m_positions;       // Array to store position objects
    string m_symbol;             // Symbol to manage
    int m_atrHandleH4;           // 4-hour ATR handle
    int m_atrHandleH1;           // 1-hour ATR handle
    int m_maxPyramids;           // Maximum pyramid additions
    
    // Private methods
    bool TrailPosition(CPosition *pos, CTrade &trade);
    bool CheckTimeStop(CPosition *pos, CTrade &trade);
    bool AttemptPyramid(CPosition *pos, CTrade &trade);
    bool TakePartialProfit(CPosition *pos, CTrade &trade);
    double CalculateChandelierStop(CPosition *pos);
    double CalculateAnchoredVWAP(CPosition *pos);
    
public:
    CPosManager();
    ~CPosManager();
    
    // Initialization
    bool Init(string symbol, int atrHandleH4, int atrHandleH1, int maxPyramids);
    
    // Position management methods
    void ManagePositions(CTrade &trade);
    bool RegisterNewPosition(ulong ticket, ENUM_TRADE_DIRECTION direction, double entryPrice, double stopLoss, double lotSize, string tradeType);
    void RemovePosition(int index);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPosManager::CPosManager()
{
    m_symbol = "";
    m_atrHandleH4 = INVALID_HANDLE;
    m_atrHandleH1 = INVALID_HANDLE;
    m_maxPyramids = 3;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPosManager::~CPosManager()
{
    // Clean up position objects
    for(int i = 0; i < m_positions.Total(); i++)
    {
        CPosition *pos = m_positions.At(i);
        if(pos != NULL) delete pos;
    }
    m_positions.Clear();
}

//+------------------------------------------------------------------+
//| Initialize the position manager                                  |
//+------------------------------------------------------------------+
bool CPosManager::Init(string symbol, int atrHandleH4, int atrHandleH1, int maxPyramids)
{
    m_symbol = symbol;
    m_atrHandleH4 = atrHandleH4;
    m_atrHandleH1 = atrHandleH1;
    m_maxPyramids = maxPyramids;
    
    return true;
}

//+------------------------------------------------------------------+
//| Manage all open positions                                        |
//+------------------------------------------------------------------+
void CPosManager::ManagePositions(CTrade &trade)
{
    // Process all positions in reverse order (for safe removal)
    for(int i = m_positions.Total() - 1; i >= 0; i--)
    {
        CPosition *pos = m_positions.At(i);
        if(pos == NULL) continue;
        
        // Update position information
        if(!PositionSelectByTicket(pos.ticket))
        {
            // Position no longer exists, remove it
            RemovePosition(i);
            continue;
        }
        
        // Update current profit
        pos.profits = PositionGetDouble(POSITION_PROFIT);
        
        // Check time stop first
        if(CheckTimeStop(pos, trade))
        {
            // Position closed due to time stop, remove it
            RemovePosition(i);
            continue;
        }
        
        // Attempt to pyramid if position is profitable
        AttemptPyramid(pos, trade);
        
        // Check for partial profit taking
        TakePartialProfit(pos, trade);
        
        // Trail the position
        TrailPosition(pos, trade);
    }
}

//+------------------------------------------------------------------+
//| Trail a position using Chandelier and Anchored VWAP              |
//+------------------------------------------------------------------+
bool CPosManager::TrailPosition(CPosition *pos, CTrade &trade)
{
    if(pos == NULL) return false;
    
    // Calculate trailing stops
    double chandelierStop = CalculateChandelierStop(pos);
    double vwapStop = CalculateAnchoredVWAP(pos);
    
    // Determine the most conservative stop
    double newStop = 0;
    
    if(pos.direction == TRADE_DIRECTION_LONG)
    {
        // For long positions, take the higher of the two stops
        newStop = MathMax(chandelierStop, vwapStop);
        
        // Only move stop loss up, never down
        if(newStop <= pos.stopLoss) return false;
    }
    else if(pos.direction == TRADE_DIRECTION_SHORT)
    {
        // For short positions, take the lower of the two stops
        newStop = MathMin(chandelierStop, vwapStop);
        
        // Only move stop loss down, never up
        if(newStop >= pos.stopLoss) return false;
    }
    else
    {
        return false;
    }
    
    // CRITICAL: Check minimum stop distance with more buffer
    double currentPrice = SymbolInfoDouble(m_symbol, (pos.direction == TRADE_DIRECTION_LONG) ? SYMBOL_BID : SYMBOL_ASK);
    double minStopDistance = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * 
                             SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    // Add extra safety buffer (20 points)
    minStopDistance += 20 * SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    // Ensure stop respects minimum distance
    if(MathAbs(currentPrice - newStop) < minStopDistance)
    {
        Print("Stop too close to current price (", MathAbs(currentPrice - newStop), 
              " vs required ", minStopDistance, "). Skipping update.");
        return false; // Skip this update rather than trying to adjust
    }
    
    // Update the stop loss
    if(trade.PositionModify(pos.ticket, newStop, 0))
    {
        pos.stopLoss = newStop;
        Print("Successfully updated stop for position #", pos.ticket, " to ", newStop);
        return true;
    }
    else
    {
        int errorCode = GetLastError();
        Print("Failed to update stop for position #", pos.ticket, ". Error: ", errorCode);
        return false;
    }
}

//+------------------------------------------------------------------+
//| Check if position should be closed due to time stop              |
//+------------------------------------------------------------------+
bool CPosManager::CheckTimeStop(CPosition *pos, CTrade &trade)
{
    if(pos == NULL) return false;
    
    // Check if position has been open for more than 6 H4 bars
    datetime currentTime = TimeCurrent();
    if(currentTime - pos.openTime > 6 * PeriodSeconds(PERIOD_H4))
    {
        // Check if position is not profitable (less than 1R)
        double currentProfit = pos.profits;
        if(currentProfit < pos.initialR)
        {
            // Close the position
            if(trade.PositionClose(pos.ticket))
            {
                Print("Time stop triggered for position #", pos.ticket);
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Attempt to add a pyramid position                                |
//+------------------------------------------------------------------+
bool CPosManager::AttemptPyramid(CPosition *pos, CTrade &trade)
{
    if(pos == NULL) return false;
    
    // Check if we can add more pyramid positions
    if(pos.pyramidCount >= m_maxPyramids)
    {
        Print("Maximum pyramid count reached for position #", pos.ticket);
        return false;
    }
    
    // Check if position is in profit by at least 1R
    if(pos.profits < pos.initialR) return false;
    
    // Calculate the size for the pyramid addition (0.3% of equity)
    double accountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double addSize = 0.003 * accountEquity; // 0.3% of equity
    
    // Check if we have enough open profit to fund the addition
    if(pos.profits < addSize) return false;
    
    // Get current price
    double entryPrice = 0;
    if(pos.direction == TRADE_DIRECTION_LONG)
    {
        entryPrice = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
    }
    else if(pos.direction == TRADE_DIRECTION_SHORT)
    {
        entryPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    }
    else
    {
        return false;
    }
    
    // Calculate lot size based on risk
    double atrH1 = 0;
    double atrBuffer[];
    if(CopyBuffer(m_atrHandleH1, 0, 0, 1, atrBuffer) > 0)
    {
        atrH1 = atrBuffer[0];
    }
    else
    {
        return false;
    }
    
    // Calculate stop loss for the pyramid addition
    double stopLoss = 0;
    if(pos.direction == TRADE_DIRECTION_LONG)
    {
        // For long positions, use the latest H1 swing low
        double swingLow = entryPrice - atrH1;
        stopLoss = swingLow;
    }
    else if(pos.direction == TRADE_DIRECTION_SHORT)
    {
        // For short positions, use the latest H1 swing high
        double swingHigh = entryPrice + atrH1;
        stopLoss = swingHigh;
    }
    
    // Check minimum stop distance
    double minStopDistance = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL) * 
                             SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    
    // Ensure stop respects minimum distance
    if(MathAbs(entryPrice - stopLoss) < minStopDistance)
    {
        // Adjust the stop to respect minimum distance
        if(pos.direction == TRADE_DIRECTION_LONG)
            stopLoss = entryPrice - minStopDistance - 5 * SymbolInfoDouble(m_symbol, SYMBOL_POINT); // Extra buffer
        else
            stopLoss = entryPrice + minStopDistance + 5 * SymbolInfoDouble(m_symbol, SYMBOL_POINT); // Extra buffer
    }
    
    // Calculate stop distance and lot size
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
    double lotSize = addSize / (stopDistance / tickSize * tickValue);
    
    // Normalize lot size
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Execute the pyramid addition
    bool result = false;
    if(pos.direction == TRADE_DIRECTION_LONG)
    {
        result = trade.Buy(lotSize, m_symbol, 0, stopLoss, 0, "Pyramid-" + IntegerToString(pos.pyramidCount + 1));
    }
    else if(pos.direction == TRADE_DIRECTION_SHORT)
    {
        result = trade.Sell(lotSize, m_symbol, 0, stopLoss, 0, "Pyramid-" + IntegerToString(pos.pyramidCount + 1));
    }
    
    // Update position if successful
    if(result)
    {
        pos.pyramidCount++;
        
        // Update the stop loss for all positions in this direction
        for(int i = 0; i < m_positions.Total(); i++)
        {
            CPosition *position = m_positions.At(i);
            if(position != NULL && position.direction == pos.direction)
            {
                trade.PositionModify(position.ticket, stopLoss, 0);
                position.stopLoss = stopLoss;
            }
        }
        
        Print("Added pyramid #", pos.pyramidCount, " to position #", pos.ticket);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Take partial profit if conditions are met                        |
//+------------------------------------------------------------------+
bool CPosManager::TakePartialProfit(CPosition *pos, CTrade &trade)
{
    if(pos == NULL) return false;
    
    // Only take partial profit if we have pyramided at least twice
    if(pos.pyramidCount < 2) return false;
    
    // Check if position is in profit by at least 2R
    if(pos.profits < 2 * pos.initialR) return false;
    
    // Calculate the size to take off (25% of position)
    double totalLots = PositionGetDouble(POSITION_VOLUME);
    double lotsToClose = totalLots * 0.25;
    double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
    
    // Ensure minimum lot size
    if(lotsToClose < minLot) lotsToClose = minLot;
    
    // Ensure we don't close more than we have
    if(lotsToClose > totalLots) lotsToClose = totalLots;
    
    // Close partial position
    if(trade.PositionClosePartial(pos.ticket, lotsToClose))
    {
        Print("Took 25% partial profit on position #", pos.ticket);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Chandelier Stop level                                  |
//+------------------------------------------------------------------+
double CPosManager::CalculateChandelierStop(CPosition *pos)
{
    if(pos == NULL) return 0;
    
    // Get ATR value
    double atrValue = 0;
    double atrBuffer[];
    
    if(CopyBuffer(m_atrHandleH4, 0, 0, 1, atrBuffer) > 0)
    {
        atrValue = atrBuffer[0];
    }
    else
    {
        return 0;
    }
    
    // Get highest/lowest close since position opened
    double highestClose = 0;
    double lowestClose = DBL_MAX;
    double closes[];
    
    if(CopyClose(m_symbol, PERIOD_H4, 0, 10, closes) > 0)
    {
        for(int i = 0; i < ArraySize(closes); i++)
        {
            highestClose = MathMax(highestClose, closes[i]);
            lowestClose = MathMin(lowestClose, closes[i]);
        }
    }
    else
    {
        return 0;
    }
    
    // Calculate Chandelier Stop
    double stopLevel = 0;
    
    if(pos.direction == TRADE_DIRECTION_LONG)
    {
        stopLevel = highestClose - 3 * atrValue;
    }
    else if(pos.direction == TRADE_DIRECTION_SHORT)
    {
        stopLevel = lowestClose + 3 * atrValue;
    }
    
    return stopLevel;
}

//+------------------------------------------------------------------+
//| Calculate Anchored VWAP level                                    |
//+------------------------------------------------------------------+
double CPosManager::CalculateAnchoredVWAP(CPosition *pos)
{
    if(pos == NULL) return 0;
    
    // This is a simplified implementation of Anchored VWAP
    // A full implementation would anchor from significant price swing points
    
    // Use position open time as anchor point
    datetime anchorTime = pos.openTime;
    
    // Calculate VWAP from anchor time to now
    double sumPriceVolume = 0;
    double sumVolume = 0;
    
    int bars = iBars(m_symbol, PERIOD_H1);
    datetime barTimes[];
    double closes[];
    long volumes[];  // Use long type for tick volumes
    
    // Get data from anchor time to now
    if(CopyTime(m_symbol, PERIOD_H1, 0, bars, barTimes) > 0 &&
       CopyClose(m_symbol, PERIOD_H1, 0, bars, closes) > 0 &&
       CopyTickVolume(m_symbol, PERIOD_H1, 0, bars, volumes) > 0)
    {
        // Calculate weighted price - use explicit cast from long to double
         for(int i = 0; i < ArraySize(barTimes); i++)
         {
             // Skip bars before anchor time
             if(barTimes[i] < anchorTime) continue;
             
             // Calculate weighted price with explicit cast
             double volAsDouble = (double)volumes[i]; // Explicit cast
             sumPriceVolume += closes[i] * volAsDouble;
             sumVolume += volAsDouble;
         }
    }
    else
    {
        return 0;
    }
    
    // Calculate VWAP
    double vwap = 0;
    if(sumVolume > 0)
    {
        vwap = sumPriceVolume / sumVolume;
    }
    
    return vwap;
}

//+------------------------------------------------------------------+
//| Register a new position                                          |
//+------------------------------------------------------------------+
bool CPosManager::RegisterNewPosition(ulong ticket, ENUM_TRADE_DIRECTION direction, double entryPrice, double stopLoss, double lotSize, string tradeType)
{
    if(!PositionSelectByTicket(ticket)) return false;
    
    // Calculate initial risk
    double tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
    double stopDistance = MathAbs(entryPrice - stopLoss);
    double initialRisk = (stopDistance / tickSize) * tickValue * lotSize;
    
    // Create a new position object
    CPosition *pos = new CPosition();
    if(pos == NULL) return false;
    
    // Set position properties
    pos.ticket = ticket;
    pos.direction = direction;
    pos.entryPrice = entryPrice;
    pos.stopLoss = stopLoss;
    pos.lotSize = lotSize;
    pos.tradeType = tradeType;
    pos.openTime = TimeCurrent();
    pos.initialR = initialRisk;
    pos.pyramidCount = 0;
    pos.profits = 0;
    
    // Add to collection
    bool result = m_positions.Add(pos);
    if(!result)
    {
        delete pos;
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Remove a position from management                                |
//+------------------------------------------------------------------+
void CPosManager::RemovePosition(int index)
{
    if(index < 0 || index >= m_positions.Total()) return;
    
    CPosition *pos = m_positions.At(index);
    if(pos != NULL) delete pos;
    
    m_positions.Delete(index);
}
//+------------------------------------------------------------------+
//|                                               MacroFilter.mqh     |
//|                                               Bongo Seakhoa       |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""

#include "Common.mqh"

// Class for macro market filtering
class CMacroFilter
{
private:
    int m_emaHandle;            // Handle to EMA indicator for DXY
    bool m_enabled;             // Flag to enable/disable the filter
    
    // Private methods
    bool CheckDXYTrend(ENUM_TRADE_DIRECTION direction);
    bool CheckVolatility();
    
public:
    CMacroFilter();
    ~CMacroFilter();
    
    // Initialization
    bool Init(int emaHandle, bool enabled);
    
    // Main filter check method
    bool CheckFilter(ENUM_TRADE_DIRECTION direction);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CMacroFilter::CMacroFilter()
{
    m_emaHandle = INVALID_HANDLE;
    m_enabled = true;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CMacroFilter::~CMacroFilter()
{
}

//+------------------------------------------------------------------+
//| Initialize the macro filter                                      |
//+------------------------------------------------------------------+
bool CMacroFilter::Init(int emaHandle, bool enabled)
{
    m_emaHandle = emaHandle;
    m_enabled = enabled;
    
    return true;
}

//+------------------------------------------------------------------+
//| Main filter check method                                         |
//+------------------------------------------------------------------+
bool CMacroFilter::CheckFilter(ENUM_TRADE_DIRECTION direction)
{
    if(!m_enabled) return true; // If filter is disabled, always pass
    
    // Check DXY trend first
    if(!CheckDXYTrend(direction)) return false;
    
    // Check volatility conditions
    if(!CheckVolatility()) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if DXY trend favors the trade direction                    |
//+------------------------------------------------------------------+
bool CMacroFilter::CheckDXYTrend(ENUM_TRADE_DIRECTION direction)
{
    // If we don't have a valid EMA handle, skip this check
    if(m_emaHandle == INVALID_HANDLE) return true;
    
    // Get EMA values
    double emaValues[];
    if(CopyBuffer(m_emaHandle, 0, 0, 2, emaValues) != 2) return true; // Skip if can't get data
    
    // Determine DXY trend
    double emaSlope = emaValues[0] - emaValues[1];
    
    // Check if DXY trend aligns with trade direction for USD pairs
    bool isDollarPair = true; // Assume it's a USD pair for now
    
    if(isDollarPair)
    {
        // For USD pairs, rising DXY typically means USD strength
        if(direction == TRADE_DIRECTION_LONG)
        {
            // For USD base pairs (like USDJPY), long = USD strength
            return (emaSlope > 0);
        }
        else if(direction == TRADE_DIRECTION_SHORT)
        {
            // For USD quote pairs (like EURUSD), short = USD strength
            return (emaSlope > 0);
        }
    }
    
    return true; // Default pass
}

//+------------------------------------------------------------------+
//| Check if volatility conditions are favorable                     |
//+------------------------------------------------------------------+
bool CMacroFilter::CheckVolatility()
{
    // Calculate 1-week realized volatility
    double weeklyReturns[60]; // Past 60 days
    double closes[61]; // Need 61 points to calculate 60 returns
    
    // Get closing prices for DXY (or any suitable proxy)
    if(CopyClose("USDX", PERIOD_D1, 0, 61, closes) != 61)
    {
        // If we can't get DXY data, try the symbol's own volatility
        if(CopyClose(Symbol(), PERIOD_D1, 0, 61, closes) != 61)
        {
            return true; // Skip this check if we can't get enough data
        }
    }
    
    // Calculate daily returns
    for(int i = 0; i < 60; i++)
    {
        weeklyReturns[i] = (closes[i] - closes[i+1]) / closes[i+1] * 100; // Percentage return
    }
    
    // Calculate 5-day rolling sum of absolute returns (proxy for weekly realized vol)
    double weeklyVol = 0;
    for(int i = 0; i < 5; i++)
    {
        weeklyVol += MathAbs(weeklyReturns[i]);
    }
    
    // Calculate 60-day median volatility
    double medianVol = 0;
    double tempVols[60];
    
    for(int i = 0; i < 56; i++) // 56 = 60 - 5 + 1 (to get 5-day windows)
    {
        double vol = 0;
        for(int j = 0; j < 5; j++)
        {
            vol += MathAbs(weeklyReturns[i+j]);
        }
        tempVols[i] = vol;
    }
    
    // Sort for median calculation
    ArraySort(tempVols);
    medianVol = (tempVols[27] + tempVols[28]) / 2; // Median of 56 values
    
    // Check if current weekly vol is below 60-day median
    return (weeklyVol < medianVol);
}
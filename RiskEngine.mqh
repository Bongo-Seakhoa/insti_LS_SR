//+------------------------------------------------------------------+
//|                                                RiskEngine.mqh     |
//|                                               Bongo Seakhoa       |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""

#include "Common.mqh"  // Include Common.mqh for ENUM_TRADE_DIRECTION

// Class for risk management
class CRiskEngine
{
private:
    double m_baseRiskPct;           // Base risk percentage
    double m_maxDrawdown;           // Maximum allowed drawdown
    
    double m_initialEquity;         // Initial account equity
    double m_peakEquity;            // Peak account equity
    double m_currentDrawdown;       // Current drawdown
    
    double m_dailyLoss;             // Current day's loss
    datetime m_lastDayChecked;      // Last day checked for daily loss
    
    double m_openRisk;              // Current open risk
    double m_varLimit;              // VaR limit
    
    // Private methods
    double CalculateVaR();
    void UpdateDrawdownStatus();
    void ResetDailyLoss();
    
    // Helper method to extract day from datetime
    int ExtractDay(datetime time)
    {
        MqlDateTime timeStruct;
        TimeToStruct(time, timeStruct);
        return timeStruct.day;
    }
    
public:
    CRiskEngine();
    ~CRiskEngine();
    
    // Initialization
    bool Init(double baseRiskPct, double maxDrawdown);
    
    // Main risk management methods
    bool CanOpenNewTrades();
    void UpdateRiskStatus();
    bool CheckCorrelationRisk(ENUM_TRADE_DIRECTION direction, double lotSize);
    
    // Trade registration methods
    void RegisterNewTrade(ENUM_TRADE_DIRECTION direction, double lotSize, double stopDistance);
    void RegisterPendingOrder(ENUM_TRADE_DIRECTION direction, double lotSize, double stopDistance);
    void RegisterClosedTrade(double profit);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CRiskEngine::CRiskEngine()
{
    m_baseRiskPct = 0.5;
    m_maxDrawdown = 15.0;
    m_initialEquity = 0;
    m_peakEquity = 0;
    m_currentDrawdown = 0;
    m_dailyLoss = 0;
    m_lastDayChecked = 0;
    m_openRisk = 0;
    m_varLimit = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CRiskEngine::~CRiskEngine()
{
}

//+------------------------------------------------------------------+
//| Initialize the risk engine                                       |
//+------------------------------------------------------------------+
bool CRiskEngine::Init(double baseRiskPct, double maxDrawdown)
{
    m_baseRiskPct = baseRiskPct;
    m_maxDrawdown = maxDrawdown;
    
    // Initialize equity values
    m_initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_peakEquity = m_initialEquity;
    
    // Initialize time check
    m_lastDayChecked = TimeCurrent();
    
    // Calculate initial VaR limit
    m_varLimit = CalculateVaR();
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if new trades can be opened                                |
//+------------------------------------------------------------------+
bool CRiskEngine::CanOpenNewTrades()
{
    // Update risk status first
    UpdateRiskStatus();
    
    // Check daily loss stop
    if(m_dailyLoss >= 2.0 * (m_baseRiskPct / 100.0) * m_initialEquity)
    {
        Print("Daily loss limit reached. No new trades allowed.");
        return false;
    }
    
    // Check drawdown ladder
    if(m_currentDrawdown >= m_maxDrawdown)
    {
        Print("Maximum drawdown reached. No new trades allowed.");
        return false;
    }
    
    // Check VaR throttle
    if(m_openRisk + m_dailyLoss > m_varLimit)
    {
        Print("VaR risk budget exceeded. No new trades allowed.");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update risk status based on current account                      |
//+------------------------------------------------------------------+
void CRiskEngine::UpdateRiskStatus()
{
    // Check if we need to reset daily loss counter
    datetime currentTime = TimeCurrent();
    if(ExtractDay(currentTime) != ExtractDay(m_lastDayChecked))
    {
        ResetDailyLoss();
        m_lastDayChecked = currentTime;
        
        // Also recalculate VaR on new day
        m_varLimit = CalculateVaR();
        Print("New day: Reset daily loss and recalculated VaR to ", m_varLimit);
    }
    
    // Update drawdown status
    UpdateDrawdownStatus();
    
    // Periodically check and reset open risk if it seems too high
    // (This prevents risk lockup in case of missed trade closures)
    static datetime lastRiskCheck = 0;
    if(currentTime - lastRiskCheck > PeriodSeconds(PERIOD_H4))
    {
        // Calculate actual open risk based on current positions
        double actualOpenRisk = 0;
        int totalPositions = PositionsTotal();
        
        for(int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            // Skip other symbols
            if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
            
            double positionVolume = PositionGetDouble(POSITION_VOLUME);
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double stopLoss = PositionGetDouble(POSITION_SL);
            
            // If position has a stop loss, calculate risk
            if(stopLoss > 0)
            {
                double stopDistance = MathAbs(entryPrice - stopLoss);
                double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
                double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
                
                actualOpenRisk += (stopDistance / tickSize) * tickValue * positionVolume;
            }
        }
        
        // If tracked risk is significantly higher than actual, adjust it down
        if(m_openRisk > actualOpenRisk * 1.5 && actualOpenRisk > 0)
        {
            Print("Adjusting tracked open risk from ", m_openRisk, " to ", actualOpenRisk);
            m_openRisk = actualOpenRisk;
            m_varLimit = CalculateVaR(); // Recalculate VaR after adjustment
        }
        
        lastRiskCheck = currentTime;
    }
    
    // Recalculate VaR limit periodically (less frequently)
    static datetime lastVaRUpdate = 0;
    if(currentTime - lastVaRUpdate > PeriodSeconds(PERIOD_D1))
    {
        m_varLimit = CalculateVaR();
        lastVaRUpdate = currentTime;
    }
}

//+------------------------------------------------------------------+
//| Check correlation risk with existing positions                   |
//+------------------------------------------------------------------+
bool CRiskEngine::CheckCorrelationRisk(ENUM_TRADE_DIRECTION direction, double lotSize)
{
    // Get list of open positions
    int totalPositions = PositionsTotal();
    double totalCorrelatedRisk = 0.0;
    bool highCorrelationDetected = false;
    
    for(int i = 0; i < totalPositions; i++)
    {
        ulong positionTicket = PositionGetTicket(i);
        if(positionTicket <= 0) continue;
        
        // Skip positions of other symbols
        if(PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        
        ENUM_TRADE_DIRECTION posDirection = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                                          TRADE_DIRECTION_LONG : TRADE_DIRECTION_SHORT;
                                          
        // If this position has opposite direction, it reduces correlation risk
        if(posDirection != direction) continue;
        
        // Calculate position risk
        double posLots = PositionGetDouble(POSITION_VOLUME);
        double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double posStopLoss = PositionGetDouble(POSITION_SL);
        
        // If no stop loss, estimate risk based on initial risk
        double posRisk = 0.0;
        if(posStopLoss > 0)
        {
            double stopDistance = MathAbs(posOpenPrice - posStopLoss);
            double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
            double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
            posRisk = (stopDistance / tickSize) * tickValue * posLots;
        }
        else
        {
            // Estimate based on initial risk
            posRisk = AccountInfoDouble(ACCOUNT_BALANCE) * (m_baseRiskPct / 100.0);
        }
        
        // Add to total correlated risk
        totalCorrelatedRisk += posRisk;
        
        // Check correlation
        double correlation = 0.75; // This is a simplified placeholder. Real implementation would calculate actual correlation.
        if(MathAbs(correlation) > 0.75)
        {
            highCorrelationDetected = true;
        }
    }
    
    // Calculate new position risk
    double newPosRisk = AccountInfoDouble(ACCOUNT_BALANCE) * (m_baseRiskPct / 100.0);
    
    // Check if combined risk exceeds cap when correlation is high
    if(highCorrelationDetected && totalCorrelatedRisk + newPosRisk > AccountInfoDouble(ACCOUNT_BALANCE) * (m_baseRiskPct / 100.0))
    {
        return false; // Risk cap exceeded
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Register a new trade                                             |
//+------------------------------------------------------------------+
void CRiskEngine::RegisterNewTrade(ENUM_TRADE_DIRECTION direction, double lotSize, double stopDistance)
{
    // Calculate the risk amount
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double riskAmount = (stopDistance / tickSize) * tickValue * lotSize;
    
    // Add to open risk
    m_openRisk += riskAmount;
}

//+------------------------------------------------------------------+
//| Register a pending order                                         |
//+------------------------------------------------------------------+
void CRiskEngine::RegisterPendingOrder(ENUM_TRADE_DIRECTION direction, double lotSize, double stopDistance)
{
    // For pending orders, we add a reduced risk since they might not be triggered
    double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double riskAmount = (stopDistance / tickSize) * tickValue * lotSize * 0.5; // 50% of actual risk
    
    // Add to open risk
    m_openRisk += riskAmount;
}

//+------------------------------------------------------------------+
//| Register a closed trade                                          |
//+------------------------------------------------------------------+
void CRiskEngine::RegisterClosedTrade(double profit)
{
    // Reduce open risk - more aggressively reset when a position is closed
    m_openRisk = MathMax(0, m_openRisk - MathAbs(profit) * 1.5);
    
    // If more than half of open risk has been closed, recalculate VaR limit
    static double lastOpenRisk = 0;
    if(lastOpenRisk > 0 && m_openRisk < lastOpenRisk * 0.5)
    {
        m_varLimit = CalculateVaR();
        lastOpenRisk = m_openRisk;
        Print("Recalculated VaR limit after significant position closure: ", m_varLimit);
    }
    
    // Update daily loss counter if trade was a loss
    if(profit < 0)
    {
        m_dailyLoss += MathAbs(profit);
    }
    
    // Update peak equity if profit
    if(profit > 0)
    {
        double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(currentEquity > m_peakEquity)
        {
            m_peakEquity = currentEquity;
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Value at Risk                                          |
//+------------------------------------------------------------------+
double CRiskEngine::CalculateVaR()
{
    // Enhanced VaR calculation: 
    // Start with a base percentage of account equity, then adjust based on recent performance
    double baseVaR = 0.02 * AccountInfoDouble(ACCOUNT_EQUITY);
    
    // If we're in a drawdown, increase VaR tolerance slightly to avoid getting stuck
    if(m_currentDrawdown > 0)
    {
        // Add a recovery factor that increases with time in drawdown
        static datetime drawdownStartTime = 0;
        if(drawdownStartTime == 0 && m_currentDrawdown > 3.0)
        {
            drawdownStartTime = TimeCurrent();
        }
        else if(m_currentDrawdown <= 1.0)
        {
            drawdownStartTime = 0; // Reset when drawdown is small
        }
        
        // After 24 hours in drawdown, gradually increase VaR tolerance
        if(drawdownStartTime > 0)
        {
            int hoursInDrawdown = (int)((TimeCurrent() - drawdownStartTime) / 3600);
            if(hoursInDrawdown > 24)
            {
                // Increase VaR by up to 50% based on time in drawdown
                double recoveryFactor = MathMin(0.5, hoursInDrawdown / 240.0); // Max 50% increase after 10 days
                baseVaR *= (1.0 + recoveryFactor);
                Print("Applied recovery factor to VaR: ", recoveryFactor, ". New VaR: ", baseVaR);
            }
        }
    }
    
    return baseVaR;
}

//+------------------------------------------------------------------+
//| Update drawdown status                                           |
//+------------------------------------------------------------------+
void CRiskEngine::UpdateDrawdownStatus()
{
    // Get current equity
    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Update peak equity if current equity is higher
    if(currentEquity > m_peakEquity)
    {
        m_peakEquity = currentEquity;
    }
    
    // Calculate current drawdown percentage
    if(m_peakEquity > 0)
    {
        m_currentDrawdown = 100.0 * (m_peakEquity - currentEquity) / m_peakEquity;
    }
    else
    {
        m_currentDrawdown = 0;
    }
}

//+------------------------------------------------------------------+
//| Reset daily loss counter                                         |
//+------------------------------------------------------------------+
void CRiskEngine::ResetDailyLoss()
{
    m_dailyLoss = 0;
}
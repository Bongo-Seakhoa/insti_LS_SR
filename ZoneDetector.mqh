//+------------------------------------------------------------------+
//|                                              ZoneDetector.mqh     |
//|                                               Bongo Seakhoa       |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""

#include <Arrays\ArrayObj.mqh>
#include "Common.mqh"

// Class for zone objects to store in CArrayObj
class CZone : public CObject
{
public:
    double midPrice;            // Middle price of the zone
    double width;               // Width of the zone
    int strength;               // Strength of the zone (based on touches and age)
    bool pendingFade;           // Flag for pending fade setup
    ENUM_TRADE_DIRECTION fadeDirection; // Direction for fade entry
    ENUM_TRADE_DIRECTION breakDirection; // Direction of zone break
    datetime breakTime;         // Time when the zone was broken
    datetime lastTradeTime;     // Time of last trade on this zone
    
    CZone()
    {
        midPrice = 0;
        width = 0;
        strength = 0;
        pendingFade = false;
        fadeDirection = TRADE_DIRECTION_NONE;
        breakDirection = TRADE_DIRECTION_NONE;
        breakTime = 0;
        lastTradeTime = 0;
    }
    
    // Required for proper sorting
    virtual int Compare(const CObject *node, const int mode=0) const
    {
        const CZone *zone = (const CZone*)node;
        if(strength > zone.strength) return 1;
        if(strength < zone.strength) return -1;
        return 0;
    }
};

// Class for detecting support and resistance zones
class CZoneDetector
{
private:
    CArrayObj m_zones;          // Array to store zone objects
    string m_symbol;            // Symbol to analyze
    double m_zoneDepthATR;      // Zone depth as multiplier of ATR
    int m_atrHandle;            // Handle to ATR indicator
    
    // Private methods
    bool DetectFractalPivots(double &pivotPrices[], bool &isPivotHigh[]);
    bool ClusterPivots(double &pivotPrices[], bool &isPivotHigh[], double atrValue);
    int CalculateZoneStrength(double midPrice, datetime firstTouch);
    bool IsNearExistingZone(double price, double width);
    
public:
    CZoneDetector();
    ~CZoneDetector();
    
    // Initialization
    bool Init(string symbol, double zoneDepthATR, int atrHandle);
    
    // Main zone detection method
    bool DetectZones();
    
    // Zone access methods
    int GetZoneCount() { return m_zones.Total(); }
    bool GetZone(int index, SZone &zone);
    bool UpdateZone(int index, SZone &zone);
    bool AddZone(SZone &zone);
    void ClearZones() { m_zones.Clear(); }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CZoneDetector::CZoneDetector()
{
    m_symbol = "";
    m_zoneDepthATR = 0.5;
    m_atrHandle = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CZoneDetector::~CZoneDetector()
{
    ClearZones();
}

//+------------------------------------------------------------------+
//| Initialize the zone detector                                     |
//+------------------------------------------------------------------+
bool CZoneDetector::Init(string symbol, double zoneDepthATR, int atrHandle)
{
    m_symbol = symbol;
    m_zoneDepthATR = zoneDepthATR;
    m_atrHandle = atrHandle;
    
    // Validate inputs
    if(m_symbol == "" || m_atrHandle == INVALID_HANDLE || m_zoneDepthATR <= 0)
    {
        Print("ZoneDetector initialization failed: Invalid inputs");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Main zone detection method                                       |
//+------------------------------------------------------------------+
bool CZoneDetector::DetectZones()
{
    // Clear existing zones
    ClearZones();
    
    // Get ATR value
    double atrBuffer[];
    if(CopyBuffer(m_atrHandle, 0, 0, 1, atrBuffer) <= 0)
    {
        Print("Failed to get ATR value for zone detection. Error: ", GetLastError());
        return false;
    }
    double atrValue = atrBuffer[0];
    
    // Detect fractal pivots on daily chart
    double pivotPrices[];
    bool isPivotHigh[];
    if(!DetectFractalPivots(pivotPrices, isPivotHigh))
    {
        Print("Failed to detect fractal pivots");
        return false;
    }
    
    // Cluster pivots into zones
    if(!ClusterPivots(pivotPrices, isPivotHigh, atrValue))
    {
        Print("Failed to cluster pivots into zones");
        return false;
    }
    
    // Sort zones by strength (keep only top 8)
    m_zones.Sort(0); // Use the Compare method we defined
    
    // Keep only top 8 zones (reverse order to have strongest first)
    m_zones.Sort(1); // Sort in descending order
    while(m_zones.Total() > 8)
    {
        m_zones.Delete(m_zones.Total() - 1);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect fractal pivots on daily chart                             |
//+------------------------------------------------------------------+
bool CZoneDetector::DetectFractalPivots(double &pivotPrices[], bool &isPivotHigh[])
{
    const int MAX_PIVOTS = 100;  // Maximum number of pivots to detect
    
    // Initialize arrays
    ArrayResize(pivotPrices, 0);
    ArrayResize(isPivotHigh, 0);
    
    // Get daily chart data
    double high[], low[];
    if(CopyHigh(m_symbol, PERIOD_D1, 0, 200, high) <= 0 || 
       CopyLow(m_symbol, PERIOD_D1, 0, 200, low) <= 0)
    {
        Print("Failed to get price data for pivot detection. Error: ", GetLastError());
        return false;
    }
    
    // Detect 3-bar fractal pivots
    for(int i = 2; i < ArraySize(high) - 2; i++)
    {
        // Check for highs
        if(high[i] > high[i-1] && high[i] > high[i-2] && 
           high[i] > high[i+1] && high[i] > high[i+2])
        {
            ArrayResize(pivotPrices, ArraySize(pivotPrices) + 1);
            ArrayResize(isPivotHigh, ArraySize(isPivotHigh) + 1);
            
            pivotPrices[ArraySize(pivotPrices) - 1] = high[i];
            isPivotHigh[ArraySize(isPivotHigh) - 1] = true;
            
            if(ArraySize(pivotPrices) >= MAX_PIVOTS) break;
        }
        
        // Check for lows
        if(low[i] < low[i-1] && low[i] < low[i-2] && 
           low[i] < low[i+1] && low[i] < low[i+2])
        {
            ArrayResize(pivotPrices, ArraySize(pivotPrices) + 1);
            ArrayResize(isPivotHigh, ArraySize(isPivotHigh) + 1);
            
            pivotPrices[ArraySize(pivotPrices) - 1] = low[i];
            isPivotHigh[ArraySize(isPivotHigh) - 1] = false;
            
            if(ArraySize(pivotPrices) >= MAX_PIVOTS) break;
        }
    }
    
    return (ArraySize(pivotPrices) > 0);
}

//+------------------------------------------------------------------+
//| Cluster pivots into zones                                        |
//+------------------------------------------------------------------+
bool CZoneDetector::ClusterPivots(double &pivotPrices[], bool &isPivotHigh[], double atrValue)
{
    // Calculate cluster width based on ATR
    double clusterWidth = atrValue * m_zoneDepthATR;
    
    // Process each pivot
    for(int i = 0; i < ArraySize(pivotPrices); i++)
    {
        double pivotPrice = pivotPrices[i];
        
        // Check if this pivot is close to an existing zone
        if(IsNearExistingZone(pivotPrice, clusterWidth))
        {
            continue; // Skip this pivot, already represented in a zone
        }
        
        // Find all pivots that belong to this cluster
        int sweepCount = 0;
        datetime firstTouch = 0;
        double sumPrices = pivotPrice;
        int countPrices = 1;
        
        // Find other pivots within the cluster range
        for(int j = 0; j < ArraySize(pivotPrices); j++)
        {
            if(i == j) continue; // Skip self
            
            // Check if pivot j is within cluster range of pivot i
            if(MathAbs(pivotPrices[j] - pivotPrice) <= clusterWidth)
            {
                sumPrices += pivotPrices[j];
                countPrices++;
                sweepCount++; // Each additional touch counts as a sweep
            }
        }
        
        // If we have at least 2 pivots in the cluster, create a zone
        if(countPrices >= 2)
        {
            // Create a new zone
            CZone *newZone = new CZone();
            if(newZone == NULL) continue;
            
            newZone.midPrice = sumPrices / countPrices;
            newZone.width = clusterWidth;
            
            // Calculate zone strength (sweeps² × ln(age))
            firstTouch = iTime(m_symbol, PERIOD_D1, 200); // Approximate first touch time
            newZone.strength = CalculateZoneStrength(newZone.midPrice, firstTouch);
            
            // Add the zone to the collection
            if(!m_zones.Add(newZone))
            {
                delete newZone;
                continue;
            }
        }
    }
    
    return (m_zones.Total() > 0);
}

//+------------------------------------------------------------------+
//| Calculate zone strength based on touches and age                 |
//+------------------------------------------------------------------+
int CZoneDetector::CalculateZoneStrength(double midPrice, datetime firstTouch)
{
    // Count how many times price has touched this zone
    int sweepCount = 0;
    
    // Get historical price data
    double high[], low[];
    if(CopyHigh(m_symbol, PERIOD_D1, 0, 200, high) <= 0 || 
       CopyLow(m_symbol, PERIOD_D1, 0, 200, low) <= 0)
    {
        return 1; // Default minimal strength
    }
    
    // Define zone boundaries
    double upperBound = midPrice + m_zoneDepthATR/2;
    double lowerBound = midPrice - m_zoneDepthATR/2;
    
    // Count sweeps (penetrations and reversals)
    bool aboveZone = false;
    bool belowZone = false;
    bool inZone = false;
    
    for(int i = ArraySize(high) - 1; i >= 0; i--)
    {
        // Detect transitions
        bool wasAboveZone = aboveZone;
        bool wasBelowZone = belowZone;
        bool wasInZone = inZone;
        
        // Determine current position relative to zone
        aboveZone = low[i] > upperBound;
        belowZone = high[i] < lowerBound;
        inZone = !aboveZone && !belowZone;
        
        // Detect sweeps (transitions into and out of the zone)
        if(!wasInZone && inZone) sweepCount++;
        if(wasInZone && !inZone) sweepCount++;
    }
    
    // Calculate zone age in days
    int ageInDays = (int)((TimeCurrent() - firstTouch) / 86400);
    double ageFactor = MathLog(MathMax(ageInDays, 1));
    
    // Strength formula: sweeps² × ln(age)
    int strength = (int)(sweepCount * sweepCount * ageFactor);
    
    return MathMax(1, strength);
}

//+------------------------------------------------------------------+
//| Check if price is near an existing zone                          |
//+------------------------------------------------------------------+
bool CZoneDetector::IsNearExistingZone(double price, double width)
{
    for(int i = 0; i < m_zones.Total(); i++)
    {
        CZone *zone = m_zones.At(i);
        if(zone != NULL)
        {
            // Check if price is within zone width
            if(MathAbs(price - zone.midPrice) <= width)
            {
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get zone by index                                                |
//+------------------------------------------------------------------+
bool CZoneDetector::GetZone(int index, SZone &zone)
{
    if(index < 0 || index >= m_zones.Total()) return false;
    
    CZone *zonePtr = m_zones.At(index);
    if(zonePtr == NULL) return false;
    
    // Copy zone data
    zone.midPrice = zonePtr.midPrice;
    zone.width = zonePtr.width;
    zone.strength = zonePtr.strength;
    zone.pendingFade = zonePtr.pendingFade;
    zone.fadeDirection = zonePtr.fadeDirection;
    zone.breakDirection = zonePtr.breakDirection;
    zone.breakTime = zonePtr.breakTime;
    zone.lastTradeTime = zonePtr.lastTradeTime;
    
    return true;
}

//+------------------------------------------------------------------+
//| Update zone at specified index                                   |
//+------------------------------------------------------------------+
bool CZoneDetector::UpdateZone(int index, SZone &zone)
{
    if(index < 0 || index >= m_zones.Total()) return false;
    
    CZone *zonePtr = m_zones.At(index);
    if(zonePtr == NULL) return false;
    
    // Update zone data
    zonePtr.midPrice = zone.midPrice;
    zonePtr.width = zone.width;
    zonePtr.strength = zone.strength;
    zonePtr.pendingFade = zone.pendingFade;
    zonePtr.fadeDirection = zone.fadeDirection;
    zonePtr.breakDirection = zone.breakDirection;
    zonePtr.breakTime = zone.breakTime;
    zonePtr.lastTradeTime = zone.lastTradeTime;
    
    return true;
}

//+------------------------------------------------------------------+
//| Add new zone to collection                                       |
//+------------------------------------------------------------------+
bool CZoneDetector::AddZone(SZone &zone)
{
    CZone *newZone = new CZone();
    if(newZone == NULL) return false;
    
    // Copy zone data
    newZone.midPrice = zone.midPrice;
    newZone.width = zone.width;
    newZone.strength = zone.strength;
    newZone.pendingFade = zone.pendingFade;
    newZone.fadeDirection = zone.fadeDirection;
    newZone.breakDirection = zone.breakDirection;
    newZone.breakTime = zone.breakTime;
    newZone.lastTradeTime = zone.lastTradeTime;
    
    // Add to collection
    if(!m_zones.Add(newZone))
    {
        delete newZone;
        return false;
    }
    
    return true;
}
//+------------------------------------------------------------------+
//|                                                     Common.mqh    |
//|                                               Bongo Seakhoa       |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Bongo Seakhoa"
#property link      ""

// Common enums and structs
enum ENUM_TRADE_DIRECTION
{
    TRADE_DIRECTION_NONE = 0,
    TRADE_DIRECTION_LONG = 1,
    TRADE_DIRECTION_SHORT = -1
};

// Zone structure to store zone information
struct SZone
{
    double midPrice;            // Middle price of the zone
    double width;               // Width of the zone
    int strength;               // Strength of the zone (based on touches and age)
    bool pendingFade;           // Flag for pending fade setup
    ENUM_TRADE_DIRECTION fadeDirection; // Direction for fade entry
    ENUM_TRADE_DIRECTION breakDirection; // Direction of zone break
    datetime breakTime;         // Time when the zone was broken
    datetime lastTradeTime;     // Time of last trade on this zone
    
    SZone()
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
};
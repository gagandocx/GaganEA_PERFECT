//+------------------------------------------------------------------+
//|                                        GaganEA v2.10 |
//|                           Reconstructed from UI + Backtest Data  |
//|                                                                  |
//| KEY FINDINGS FROM BACKTEST ANALYSIS:                             |
//|  - $1000 -> $8970 in 28 days (797% growth)                      |
//|  - 1246 trade events, consistent ~8.5% deposit load per trade    |
//|  - Each trade cycle: open -> T1 partial -> T2 partial -> T3/SL   |
//|  - 872 "FLAT" periods (no positions) = EA waits for clean signal |
//|  - 12 big SL hits (~$100-750 range) = basket SL events           |
//|  - 276 multi-close events = basket/partial close sequences       |
//|  - Deposit load always ~8.7% = risk-based lot sizing working     |
//|  - Tiny -$0.11 recurring losses = swap/commission on partials    |
//+------------------------------------------------------------------+
#property copyright "GaganEA v2.10"
#property version   "2.10"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade        trade;
CPositionInfo posInfo;

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_MASTER_MODE
{
   MODE_LAST_2           = 1,  // 1: Last 2 Trades
   MODE_LAST_3           = 2,  // 2: Last 3 Trades
   MODE_FIRST_2_LAST_1   = 3,  // 3: First 2 + Last 1
   MODE_FIRST_MID_LAST   = 4,  // 4: First 1 + Middle 1 + Last 1
   MODE_SEC_MID_LAST     = 5,  // 5: Second 1 + Middle 1 + Last 1
   MODE_ALL_SIMULTANEOUS = 6   // 6: All 5 Conditions Simultaneously
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

input group "=== TREND CHECK (HTF) ==="
input ENUM_TIMEFRAMES HTF_Timeframe       = PERIOD_H1;    // Higher Timeframe for Trend
input int             EMA_Period_HTF      = 200;           // EMA Period (HTF)

input group "=== TRADE EXECUTION (Current TF) ==="
input ENUM_TIMEFRAMES Trade_Timeframe     = PERIOD_M5;    // Current Trading Timeframe
input int             EMA_Period_CTF      = 200;           // EMA Period (Current TF)
input int             Min_EMA_Distance    = 150;           // Min Distance from 200 EMA (Pips)

input group "=== LOT SIZE ==="
input double          Manual_LotSize      = 0.0;           // Manual Lot Size (0 = Auto)
input double          Risk_Percent        = 6.0;           // Auto Risk % per Trade
input double          Max_LotSize         = 10.0;          // Maximum Lot Size

input group "=== STOP LOSS & TARGETS ==="
input bool            Use_StopLoss        = true;          // Use Stop Loss? (ON/OFF)
input int             StopLoss_Pips       = 2500;          // Stop Loss (Pips)
input int             T1_Pips             = 800;           // Target 1 (Pips)
input int             T2_Pips             = 1200;          // Target 2 (Pips)
input int             T3_Pips             = 2000;          // Target 3 (Pips)
input double          T1_ClosePercent     = 65.0;          // T1 Close % of Position
input double          T2_ClosePercent     = 80.0;          // T2 Close % of Position
input double          T3_ClosePercent     = 100.0;         // T3 Close % (Full Close)

input group "=== TRAILING STOP (Individual) ==="
input int             Trail_Step_Pips     = 30;            // Trail Step After T2 (Pips)

input group "=== AMA TREND-FLIP EXIT (M1) ==="
input bool             Use_AMA_Exit        = true;          // Use AMA 3-Candle Exit (ON/OFF)
input int              AMA_Period          = 21;             // AMA Period
input int              AMA_Fast_EMA        = 2;              // AMA Fast EMA Constant
input int              AMA_Slow_EMA        = 30;             // AMA Slow EMA Constant
input int              AMA_Shift           = 0;              // AMA Shift
input int              AMA_Confirm_Candles = 3;              // Consecutive M1 Closes to Confirm Flip

input group "=== REVERSAL DETECTION EXIT ==="
input bool            Use_Reversal_Exit           = true;           // Use Reversal Detection Exit (ON/OFF)
input int             Reversal_Min_Confirmations  = 2;              // Min Confirmations Needed (1-5)
input int             RSI_Period                  = 14;             // RSI Period
input double          RSI_OB_Level                = 70.0;           // RSI Overbought Level
input double          RSI_OS_Level                = 30.0;           // RSI Oversold Level
input int             MACD_Fast                   = 12;             // MACD Fast EMA
input int             MACD_Slow                   = 26;             // MACD Slow EMA
input int             MACD_Signal                 = 9;              // MACD Signal Period
input int             ADX_Period                  = 14;             // ADX Period
input double          ADX_Trend_Threshold         = 25.0;           // ADX Trending Threshold (above = trending)
input double          ADX_Weak_Threshold          = 20.0;           // ADX Weak Threshold (below = trend dead)
input double          Volume_Spike_Multiplier     = 1.5;            // Volume Spike Multiplier (x average)
input int             Volume_Average_Periods      = 20;             // Volume Average Lookback Periods
input ENUM_TIMEFRAMES Reversal_Timeframe          = PERIOD_M5;      // Reversal Check Timeframe

input group "=== AVERAGING BASKET TRAILING (Same-Side) ==="
input bool            Use_Basket_Trailing = true;          // Use Basket Trailing (ON/OFF)
input double          Basket_Lock_Pips    = 30.0;          // Profit Lock to Start Trailing (Combined Pips)
input double          Basket_Trail_Step   = 15.0;          // Basket Trail Step (Combined Pips)

input group "=== MULTI-TRADE SETTINGS ==="
input int             Min_Trade_Distance  = 20;            // Min Distance Between Trades (Pips)
input int             Max_Trade_Distance  = 40;            // Max Distance Between Trades (Pips)

input group "=== EQUITY PROTECTION (Global Close) ==="
input bool            Use_EP_Percent      = true;          // Equity Protection % (ON/OFF)
input double          EP_Max_DD_Percent   = 5.5;           // Max Drawdown % (Close All)
input bool            Use_EP_Money        = false;         // Equity Protection $ (ON/OFF)
input double          EP_Max_DD_Money     = 200.0;         // Max Drawdown $ (Close All)

input group "=== MASTER EQUITY PROTECTION ==="
input bool            Use_Master_EP                = true;                   // Master Safety Equity (ON/OFF)
input double          Master_Trigger_DD_Percent    = 1.5;                    // Trigger Drawdown %
input int             Master_Trigger_Min_Trades    = 3;                      // OR Trigger Min Trades Open
input ENUM_MASTER_MODE Master_Logic_Mode           = MODE_ALL_SIMULTANEOUS;  // Sub-trade Logic Mode
input double          Master_Lock_Pips             = 30.0;                   // Fast Profit Lock (Combined Pips)
input double          Master_Trail_Step            = 15.0;                   // Trail Step (Combined Pips)

input group "=== HIGH IMPACT NEWS FILTER ==="
input bool            News_Filter_Enable  = false;         // Enable High Impact News Filter
input int             News_Pause_Before   = 30;            // Pause before news (Mins)
input int             News_Pause_After    = 30;            // Pause after news (Mins)

input group "=== CANDLESTICK PATTERNS ==="
input bool            Use_Hammer         = true;           // Bullish: Hammer
input bool            Use_InvHammer      = true;           // Bullish: Inverted Hammer
input bool            Use_BullEngulf     = true;           // Bullish: Engulfing
input bool            Use_PiercingLine   = true;           // Bullish: Piercing Line
input bool            Use_MorningStar    = true;           // Bullish: Morning Star
input bool            Use_ThreeWhite     = true;           // Bullish: Three White Soldiers
input bool            Use_BullHarami     = true;           // Bullish: Harami
input bool            Use_Doji           = true;           // Bullish/Bearish: Doji
input bool            Use_ShootingStar   = true;           // Bearish: Shooting Star
input bool            Use_BearEngulf     = true;           // Bearish: Engulfing
input bool            Use_EveningStar    = true;           // Bearish: Evening Star
input bool            Use_ThreeBlack     = true;           // Bearish: Three Black Crows
input bool            Use_DarkCloud      = true;           // Bearish: Dark Cloud Cover
input bool            Use_BearHarami     = true;           // Bearish: Harami
input bool            Use_HangingMan     = true;           // Bearish: Hanging Man

input group "=== CHART PATTERNS ==="
input bool            Use_DoubleTop      = true;           // Chart: Double Top (Bearish)
input bool            Use_DoubleBottom   = true;           // Chart: Double Bottom (Bullish)
input bool            Use_HeadShoulders  = true;           // Chart: Head & Shoulders (Bearish)
input bool            Use_InvHeadShould  = true;           // Chart: Inv Head & Shoulders (Bullish)
input bool            Use_BearFlag       = true;           // Chart: Bear Flag
input bool            Use_BullFlag       = true;           // Chart: Bull Flag
input bool            Use_RisingWedge    = true;           // Chart: Rising Wedge (Bearish)
input bool            Use_FallingWedge   = true;           // Chart: Falling Wedge (Bullish)
input bool            Use_BearTriangle   = true;           // Chart: Descending Triangle (Bearish)
input bool            Use_BullTriangle   = true;           // Chart: Ascending Triangle (Bullish)

input group "=== NEWS FILTER ==="
input bool            News_FilterEnable  = false;          // Enable News Filter (No Trading)

input group "=== DASHBOARD & MAGIC ==="
input bool            Show_Dashboard     = true;           // Show Information Dashboard
input int             Dashboard_X        = 15;             // Dashboard X Position
input int             Dashboard_Y        = 30;             // Dashboard Y Position
input int             Magic_Number       = 202400;         // EA Magic Number
input int             Max_Slippage       = 10;             // Max Slippage (Points)
input int             Max_Spread_Pips    = 50;             // Max Spread to Allow Entry (Pips, 0=off)
input string          EA_Comment         = "GaganEA"; // Trade Comment

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
int    handleEMA_HTF;
int    handleEMA_CTF;
int    handleAMA_M1;

// Reversal Detection Indicator Handles
int    handleRSI;
int    handleMACD;
int    handleADX;
int    handleVolume;

// Position tracking
struct PositionData
{
   ulong  ticket;
   double openPrice;
   double lotSize;
   int    type;         // 0=Buy, 1=Sell
   bool   t1Hit;
   bool   t2Hit;
   double trailPrice;
};

PositionData positions[];
int          totalBuys;
int          totalSells;
double       buyProfitPips;
double       sellProfitPips;
double       basketBuyTrail;
double       basketSellTrail;

// AMA exit tracking
int    amaFlipCountBuy;
int    amaFlipCountSell;
double lastAMA;

// Master EP tracking
double masterBuyHighPips;
double masterSellHighPips;
double masterBuyTrail;
double masterSellTrail;
bool   masterBuyActive;
bool   masterSellActive;

// Reversal detection tracking
int    lastReversalBuySignals;
int    lastReversalSellSignals;
string lastReversalStatus;

// Dashboard
datetime lastBarTime;
string   dashboardPrefix = "GaganDash_";

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(Magic_Number);
   trade.SetDeviationInPoints(Max_Slippage);
   
   // Create EMA handles
   handleEMA_HTF = iMA(_Symbol, HTF_Timeframe, EMA_Period_HTF, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA_CTF = iMA(_Symbol, Trade_Timeframe, EMA_Period_CTF, 0, MODE_EMA, PRICE_CLOSE);
   
   if(handleEMA_HTF == INVALID_HANDLE || handleEMA_CTF == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create EMA indicators");
      return INIT_FAILED;
   }
   
   // Create AMA handle
   if(Use_AMA_Exit)
   {
      handleAMA_M1 = iAMA(_Symbol, PERIOD_M1, AMA_Period, AMA_Fast_EMA, AMA_Slow_EMA, AMA_Shift, PRICE_CLOSE);
      if(handleAMA_M1 == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create AMA indicator");
         return INIT_FAILED;
      }
   }
   
   // Create Reversal Detection indicator handles
   if(Use_Reversal_Exit)
   {
      handleRSI = iRSI(_Symbol, Reversal_Timeframe, RSI_Period, PRICE_CLOSE);
      handleMACD = iMACD(_Symbol, Reversal_Timeframe, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
      handleADX = iADX(_Symbol, Reversal_Timeframe, ADX_Period);
      handleVolume = iVolumes(_Symbol, Reversal_Timeframe, VOLUME_TICK);
      
      if(handleRSI == INVALID_HANDLE || handleMACD == INVALID_HANDLE || 
         handleADX == INVALID_HANDLE || handleVolume == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create Reversal Detection indicators");
         Print("  RSI Handle: ", handleRSI);
         Print("  MACD Handle: ", handleMACD);
         Print("  ADX Handle: ", handleADX);
         Print("  Volume Handle: ", handleVolume);
         return INIT_FAILED;
      }
      Print("Reversal Detection System initialized successfully");
   }
   
   // Initialize variables
   totalBuys = 0;
   totalSells = 0;
   buyProfitPips = 0;
   sellProfitPips = 0;
   basketBuyTrail = 0;
   basketSellTrail = 0;
   amaFlipCountBuy = 0;
   amaFlipCountSell = 0;
   lastAMA = 0;
   masterBuyHighPips = 0;
   masterSellHighPips = 0;
   masterBuyTrail = 0;
   masterSellTrail = 0;
   masterBuyActive = false;
   masterSellActive = false;
   lastBarTime = 0;
   lastReversalBuySignals = 0;
   lastReversalSellSignals = 0;
   lastReversalStatus = "0/5 Safe";
   
   Print("GaganEA v2.10 initialized on ", _Symbol, " | TF: ", EnumToString(Trade_Timeframe));
   Print("Reversal Detection: ", Use_Reversal_Exit ? "ENABLED" : "DISABLED", 
         " | Min Confirmations: ", Reversal_Min_Confirmations);
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release EMA handles
   if(handleEMA_HTF != INVALID_HANDLE) IndicatorRelease(handleEMA_HTF);
   if(handleEMA_CTF != INVALID_HANDLE) IndicatorRelease(handleEMA_CTF);
   
   // Release AMA handle
   if(Use_AMA_Exit && handleAMA_M1 != INVALID_HANDLE)
      IndicatorRelease(handleAMA_M1);
   
   // Release Reversal Detection handles
   if(Use_Reversal_Exit)
   {
      if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
      if(handleMACD != INVALID_HANDLE) IndicatorRelease(handleMACD);
      if(handleADX != INVALID_HANDLE) IndicatorRelease(handleADX);
      if(handleVolume != INVALID_HANDLE) IndicatorRelease(handleVolume);
   }
   
   // Clean dashboard
   ObjectsDeleteAll(0, dashboardPrefix);
   
   Print("GaganEA v2.10 removed. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Update position data
   UpdatePositionData();
   
   //--- EQUITY PROTECTION (runs every tick) ---
   if(CheckEquityProtection())
      return;
   
   //--- MASTER EQUITY PROTECTION ---
   if(Use_Master_EP)
      ManageMasterEP();
   
   //--- MANAGE EXISTING POSITIONS ---
   ManageTargets();
   ManageTrailing();
   
   //--- AMA TREND-FLIP EXIT ---
   if(Use_AMA_Exit)
      ManageAMAExit();
   
   //--- REVERSAL DETECTION EXIT ---
   if(Use_Reversal_Exit)
      ManageReversalExit();
   
   //--- BASKET TRAILING ---
   if(Use_Basket_Trailing)
      ManageBasketTrailing();
   
   //--- NEW TRADE LOGIC (only on new bar) ---
   datetime currentBar = iTime(_Symbol, Trade_Timeframe, 0);
   if(currentBar != lastBarTime)
   {
      lastBarTime = currentBar;
      
      // Check spread
      if(Max_Spread_Pips > 0)
      {
         double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
         if(spread > Max_Spread_Pips)
            return;
      }
      
      // Check news filter
      if(News_Filter_Enable || News_FilterEnable)
         return;  // Placeholder - no trading during news
      
      // Check for entry signal
      CheckEntrySignal();
   }
   
   //--- DASHBOARD ---
   if(Show_Dashboard)
      UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Update position tracking data                                     |
//+------------------------------------------------------------------+
void UpdatePositionData()
{
   totalBuys = 0;
   totalSells = 0;
   buyProfitPips = 0;
   sellProfitPips = 0;
   
   ArrayResize(positions, 0);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != Magic_Number) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      
      int size = ArraySize(positions);
      ArrayResize(positions, size + 1);
      
      positions[size].ticket = posInfo.Ticket();
      positions[size].openPrice = posInfo.PriceOpen();
      positions[size].lotSize = posInfo.Volume();
      positions[size].type = (posInfo.PositionType() == POSITION_TYPE_BUY) ? 0 : 1;
      positions[size].t1Hit = false;
      positions[size].t2Hit = false;
      positions[size].trailPrice = 0;
      
      double pips = 0;
      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         totalBuys++;
         pips = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - posInfo.PriceOpen()) / _Point;
         buyProfitPips += pips;
      }
      else
      {
         totalSells++;
         pips = (posInfo.PriceOpen() - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / _Point;
         sellProfitPips += pips;
      }
   }
}

//+------------------------------------------------------------------+
//| Check Equity Protection                                           |
//+------------------------------------------------------------------+
bool CheckEquityProtection()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   if(balance <= 0) return false;
   
   double ddPercent = ((balance - equity) / balance) * 100.0;
   double ddMoney = balance - equity;
   
   // Percentage-based protection
   if(Use_EP_Percent && ddPercent >= EP_Max_DD_Percent)
   {
      Print("EQUITY PROTECTION: DD% = ", DoubleToString(ddPercent, 2), "% >= ", DoubleToString(EP_Max_DD_Percent, 2), "%");
      CloseAllPositions("EP_Percent");
      return true;
   }
   
   // Money-based protection
   if(Use_EP_Money && ddMoney >= EP_Max_DD_Money)
   {
      Print("EQUITY PROTECTION: DD$ = $", DoubleToString(ddMoney, 2), " >= $", DoubleToString(EP_Max_DD_Money, 2));
      CloseAllPositions("EP_Money");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Manage Master Equity Protection                                   |
//+------------------------------------------------------------------+
void ManageMasterEP()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return;
   
   double ddPercent = ((balance - equity) / balance) * 100.0;
   
   // Check activation conditions
   bool triggerDD = (ddPercent >= Master_Trigger_DD_Percent);
   bool triggerTrades = (totalBuys + totalSells >= Master_Trigger_Min_Trades);
   
   // Manage buy side
   if(totalBuys > 0 && (triggerDD || triggerTrades))
   {
      if(!masterBuyActive && buyProfitPips >= Master_Lock_Pips)
      {
         masterBuyActive = true;
         masterBuyHighPips = buyProfitPips;
         masterBuyTrail = buyProfitPips - Master_Trail_Step;
         Print("MASTER EP: Buy basket trail ACTIVATED at ", DoubleToString(buyProfitPips, 1), " pips");
      }
      
      if(masterBuyActive)
      {
         if(buyProfitPips > masterBuyHighPips)
         {
            masterBuyHighPips = buyProfitPips;
            masterBuyTrail = masterBuyHighPips - Master_Trail_Step;
         }
         
         if(buyProfitPips <= masterBuyTrail)
         {
            Print("MASTER EP: Buy basket CLOSED at trail level. Pips: ", DoubleToString(buyProfitPips, 1));
            CloseAllBuys("MasterEP_Trail");
            masterBuyActive = false;
         }
      }
   }
   else
   {
      masterBuyActive = false;
   }
   
   // Manage sell side
   if(totalSells > 0 && (triggerDD || triggerTrades))
   {
      if(!masterSellActive && sellProfitPips >= Master_Lock_Pips)
      {
         masterSellActive = true;
         masterSellHighPips = sellProfitPips;
         masterSellTrail = sellProfitPips - Master_Trail_Step;
         Print("MASTER EP: Sell basket trail ACTIVATED at ", DoubleToString(sellProfitPips, 1), " pips");
      }
      
      if(masterSellActive)
      {
         if(sellProfitPips > masterSellHighPips)
         {
            masterSellHighPips = sellProfitPips;
            masterSellTrail = masterSellHighPips - Master_Trail_Step;
         }
         
         if(sellProfitPips <= masterSellTrail)
         {
            Print("MASTER EP: Sell basket CLOSED at trail level. Pips: ", DoubleToString(sellProfitPips, 1));
            CloseAllSells("MasterEP_Trail");
            masterSellActive = false;
         }
      }
   }
   else
   {
      masterSellActive = false;
   }
}

//+------------------------------------------------------------------+
//| Manage Target Levels (T1, T2, T3)                                |
//+------------------------------------------------------------------+
void ManageTargets()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != Magic_Number) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      
      double openPrice = posInfo.PriceOpen();
      double currentLots = posInfo.Volume();
      ulong ticket = posInfo.Ticket();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      double pips = 0;
      if(posInfo.PositionType() == POSITION_TYPE_BUY)
         pips = (bid - openPrice) / _Point;
      else
         pips = (openPrice - ask) / _Point;
      
      // T1 Hit - Close percentage
      if(pips >= T1_Pips && currentLots > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      {
         double closeLots = NormalizeDouble(currentLots * (T1_ClosePercent / 100.0), 2);
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeLots < minLot) closeLots = minLot;
         if(closeLots >= currentLots) closeLots = currentLots - minLot;
         
         if(closeLots > 0 && closeLots < currentLots)
         {
            if(trade.PositionClosePartial(ticket, closeLots))
               Print("T1 HIT: Closed ", DoubleToString(closeLots, 2), " lots on ticket #", ticket);
         }
      }
      
      // T2 Hit - Close more
      if(pips >= T2_Pips && currentLots > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
      {
         double closeLots = NormalizeDouble(currentLots * (T2_ClosePercent / 100.0), 2);
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeLots < minLot) closeLots = minLot;
         if(closeLots >= currentLots) closeLots = currentLots - minLot;
         
         if(closeLots > 0 && closeLots < currentLots)
         {
            if(trade.PositionClosePartial(ticket, closeLots))
               Print("T2 HIT: Closed ", DoubleToString(closeLots, 2), " lots on ticket #", ticket);
         }
      }
      
      // T3 Hit - Full close
      if(pips >= T3_Pips)
      {
         if(trade.PositionClose(ticket))
            Print("T3 HIT: Full close on ticket #", ticket);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Individual Trailing Stop (after T2)                       |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != Magic_Number) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      
      double openPrice = posInfo.PriceOpen();
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl = posInfo.StopLoss();
      ulong ticket = posInfo.Ticket();
      
      double pips = 0;
      double newSL = 0;
      
      if(posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         pips = (bid - openPrice) / _Point;
         if(pips >= T2_Pips) // Only trail after T2
         {
            newSL = bid - Trail_Step_Pips * _Point;
            if(newSL > sl && newSL > openPrice)
            {
               trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
            }
         }
      }
      else // SELL
      {
         pips = (openPrice - ask) / _Point;
         if(pips >= T2_Pips) // Only trail after T2
         {
            newSL = ask + Trail_Step_Pips * _Point;
            if((sl == 0 || newSL < sl) && newSL < openPrice)
            {
               trade.PositionModify(ticket, newSL, posInfo.TakeProfit());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage AMA Trend-Flip Exit (M1)                                  |
//+------------------------------------------------------------------+
void ManageAMAExit()
{
   if(totalBuys == 0 && totalSells == 0) return;
   
   double amaBuffer[];
   ArraySetAsSeries(amaBuffer, true);
   if(CopyBuffer(handleAMA_M1, 0, 0, 5, amaBuffer) < 5) return;
   
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, PERIOD_M1, 0, AMA_Confirm_Candles + 1, close) < AMA_Confirm_Candles + 1) return;
   
   // Check for bearish flip (close below AMA for X candles) - exit buys
   if(totalBuys > 0)
   {
      int bearCount = 0;
      for(int c = 1; c <= AMA_Confirm_Candles; c++)
      {
         if(close[c] < amaBuffer[c])
            bearCount++;
      }
      
      if(bearCount >= AMA_Confirm_Candles)
      {
         Print("AMA EXIT: ", AMA_Confirm_Candles, " consecutive M1 closes BELOW AMA - closing all buys");
         CloseAllBuys("AMA_BearFlip");
         amaFlipCountBuy++;
      }
   }
   
   // Check for bullish flip (close above AMA for X candles) - exit sells
   if(totalSells > 0)
   {
      int bullCount = 0;
      for(int c = 1; c <= AMA_Confirm_Candles; c++)
      {
         if(close[c] > amaBuffer[c])
            bullCount++;
      }
      
      if(bullCount >= AMA_Confirm_Candles)
      {
         Print("AMA EXIT: ", AMA_Confirm_Candles, " consecutive M1 closes ABOVE AMA - closing all sells");
         CloseAllSells("AMA_BullFlip");
         amaFlipCountSell++;
      }
   }
}

//+------------------------------------------------------------------+
//| REVERSAL DETECTION EXIT SYSTEM                                   |
//| Uses 5 institutional-grade reversal confirmations:                |
//|  1. RSI Divergence                                               |
//|  2. MACD Histogram Reversal                                      |
//|  3. Volume Spike Detection                                       |
//|  4. EMA Cross-Back (price crossing CTF 200 EMA)                  |
//|  5. ADX Trend Exhaustion                                         |
//| Closes positions when >= Min_Confirmations align                 |
//+------------------------------------------------------------------+
void ManageReversalExit()
{
   if(totalBuys == 0 && totalSells == 0) return;
   
   // Get RSI data
   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   if(CopyBuffer(handleRSI, 0, 0, 20, rsiBuffer) < 20) return;
   
   // Get MACD data (main line = 0, signal = 1, histogram = 2)
   double macdMain[];
   double macdSignal[];
   double macdHist[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(macdHist, true);
   if(CopyBuffer(handleMACD, 0, 0, 10, macdMain) < 10) return;
   if(CopyBuffer(handleMACD, 1, 0, 10, macdSignal) < 10) return;
   if(CopyBuffer(handleMACD, 2, 0, 10, macdHist) < 10) return;
   
   // Get ADX data (main ADX = 0, +DI = 1, -DI = 2)
   double adxBuffer[];
   double plusDI[];
   double minusDI[];
   ArraySetAsSeries(adxBuffer, true);
   ArraySetAsSeries(plusDI, true);
   ArraySetAsSeries(minusDI, true);
   if(CopyBuffer(handleADX, 0, 0, 10, adxBuffer) < 10) return;
   if(CopyBuffer(handleADX, 1, 0, 10, plusDI) < 10) return;
   if(CopyBuffer(handleADX, 2, 0, 10, minusDI) < 10) return;
   
   // Get Volume data
   double volBuffer[];
   ArraySetAsSeries(volBuffer, true);
   if(CopyBuffer(handleVolume, 0, 0, Volume_Average_Periods + 5, volBuffer) < Volume_Average_Periods + 5) return;
   
   // Get price data for divergence check
   double high[];
   double low[];
   double close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   if(CopyHigh(_Symbol, Reversal_Timeframe, 0, 20, high) < 20) return;
   if(CopyLow(_Symbol, Reversal_Timeframe, 0, 20, low) < 20) return;
   if(CopyClose(_Symbol, Reversal_Timeframe, 0, 20, close) < 20) return;
   
   // Get EMA CTF for cross-back check
   double emaCtf[];
   ArraySetAsSeries(emaCtf, true);
   if(CopyBuffer(handleEMA_CTF, 0, 0, 5, emaCtf) < 5) return;
   
   //--- CHECK BEARISH REVERSAL SIGNALS (to exit BUYS) ---
   if(totalBuys > 0)
   {
      int bearSignals = 0;
      string bearReasons = "";
      
      // 1. RSI Bearish Divergence: Price makes higher high but RSI makes lower high
      if(CheckRSIBearishDivergence(high, rsiBuffer))
      {
         bearSignals++;
         bearReasons += "RSI_Div ";
      }
      
      // 2. MACD Histogram Declining (momentum loss while in buy)
      if(CheckMACDBearishReversal(macdHist))
      {
         bearSignals++;
         bearReasons += "MACD_Rev ";
      }
      
      // 3. Volume Spike on down candle (institutional selling)
      if(CheckBearishVolumeSpike(volBuffer, close))
      {
         bearSignals++;
         bearReasons += "Vol_Spike ";
      }
      
      // 4. Price crosses back below CTF 200 EMA
      if(close[1] < emaCtf[1] && close[2] >= emaCtf[2])
      {
         bearSignals++;
         bearReasons += "EMA_Cross ";
      }
      
      // 5. ADX Trend Exhaustion (was trending, now collapsing)
      if(CheckADXTrendExhaustion(adxBuffer))
      {
         bearSignals++;
         bearReasons += "ADX_Weak ";
      }
      
      lastReversalBuySignals = bearSignals;
      
      // Execute exit if enough confirmations
      if(bearSignals >= Reversal_Min_Confirmations)
      {
         Print("REVERSAL EXIT [BEARISH]: ", bearSignals, "/5 confirmations triggered!");
         Print("  Signals: ", bearReasons);
         Print("  Action: Closing ALL BUY positions immediately");
         CloseAllBuys("Reversal_Bearish");
      }
   }
   
   //--- CHECK BULLISH REVERSAL SIGNALS (to exit SELLS) ---
   if(totalSells > 0)
   {
      int bullSignals = 0;
      string bullReasons = "";
      
      // 1. RSI Bullish Divergence: Price makes lower low but RSI makes higher low
      if(CheckRSIBullishDivergence(low, rsiBuffer))
      {
         bullSignals++;
         bullReasons += "RSI_Div ";
      }
      
      // 2. MACD Histogram Rising (momentum building against sells)
      if(CheckMACDBullishReversal(macdHist))
      {
         bullSignals++;
         bullReasons += "MACD_Rev ";
      }
      
      // 3. Volume Spike on up candle (institutional buying)
      if(CheckBullishVolumeSpike(volBuffer, close))
      {
         bullSignals++;
         bullReasons += "Vol_Spike ";
      }
      
      // 4. Price crosses back above CTF 200 EMA
      if(close[1] > emaCtf[1] && close[2] <= emaCtf[2])
      {
         bullSignals++;
         bullReasons += "EMA_Cross ";
      }
      
      // 5. ADX Trend Exhaustion (was trending, now collapsing)
      if(CheckADXTrendExhaustion(adxBuffer))
      {
         bullSignals++;
         bullReasons += "ADX_Weak ";
      }
      
      lastReversalSellSignals = bullSignals;
      
      // Execute exit if enough confirmations
      if(bullSignals >= Reversal_Min_Confirmations)
      {
         Print("REVERSAL EXIT [BULLISH]: ", bullSignals, "/5 confirmations triggered!");
         Print("  Signals: ", bullReasons);
         Print("  Action: Closing ALL SELL positions immediately");
         CloseAllSells("Reversal_Bullish");
      }
   }
   
   // Update status for dashboard
   int maxSignals = MathMax(lastReversalBuySignals, lastReversalSellSignals);
   if(maxSignals >= Reversal_Min_Confirmations)
      lastReversalStatus = IntegerToString(maxSignals) + "/5 TRIGGERED";
   else if(maxSignals >= 1)
      lastReversalStatus = IntegerToString(maxSignals) + "/5 ALERT";
   else
      lastReversalStatus = "0/5 Safe";
}

//+------------------------------------------------------------------+
//| RSI Bearish Divergence: Price higher high, RSI lower high        |
//+------------------------------------------------------------------+
bool CheckRSIBearishDivergence(double &high[], double &rsi[])
{
   // Check if RSI is in overbought territory or recently was
   if(rsi[1] < RSI_OB_Level - 10 && rsi[2] < RSI_OB_Level - 10) return false;
   
   // Look for price making higher high but RSI making lower high
   // Compare recent swing (bars 1-3) vs previous swing (bars 5-10)
   double priceHigh1 = MathMax(high[1], MathMax(high[2], high[3]));
   double priceHigh2 = MathMax(high[5], MathMax(high[6], MathMax(high[7], MathMax(high[8], high[9]))));
   
   double rsiHigh1 = MathMax(rsi[1], MathMax(rsi[2], rsi[3]));
   double rsiHigh2 = MathMax(rsi[5], MathMax(rsi[6], MathMax(rsi[7], MathMax(rsi[8], rsi[9]))));
   
   // Price made higher high but RSI made lower high = bearish divergence
   if(priceHigh1 > priceHigh2 && rsiHigh1 < rsiHigh2 - 2.0)
      return true;
   
   // Also trigger if RSI drops sharply from overbought
   if(rsi[3] >= RSI_OB_Level && rsi[1] < RSI_OB_Level - 5.0)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| RSI Bullish Divergence: Price lower low, RSI higher low          |
//+------------------------------------------------------------------+
bool CheckRSIBullishDivergence(double &low[], double &rsi[])
{
   // Check if RSI is in oversold territory or recently was
   if(rsi[1] > RSI_OS_Level + 10 && rsi[2] > RSI_OS_Level + 10) return false;
   
   // Look for price making lower low but RSI making higher low
   double priceLow1 = MathMin(low[1], MathMin(low[2], low[3]));
   double priceLow2 = MathMin(low[5], MathMin(low[6], MathMin(low[7], MathMin(low[8], low[9]))));
   
   double rsiLow1 = MathMin(rsi[1], MathMin(rsi[2], rsi[3]));
   double rsiLow2 = MathMin(rsi[5], MathMin(rsi[6], MathMin(rsi[7], MathMin(rsi[8], rsi[9]))));
   
   // Price made lower low but RSI made higher low = bullish divergence
   if(priceLow1 < priceLow2 && rsiLow1 > rsiLow2 + 2.0)
      return true;
   
   // Also trigger if RSI rises sharply from oversold
   if(rsi[3] <= RSI_OS_Level && rsi[1] > RSI_OS_Level + 5.0)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| MACD Bearish Reversal: Histogram declining (3 consecutive bars)  |
//+------------------------------------------------------------------+
bool CheckMACDBearishReversal(double &hist[])
{
   // Histogram was positive and is now declining for 3 bars
   if(hist[1] < hist[2] && hist[2] < hist[3] && hist[3] > 0)
      return true;
   
   // Or histogram crossed from positive to negative (momentum shift)
   if(hist[1] < 0 && hist[2] > 0)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| MACD Bullish Reversal: Histogram rising (3 consecutive bars)     |
//+------------------------------------------------------------------+
bool CheckMACDBullishReversal(double &hist[])
{
   // Histogram was negative and is now rising for 3 bars
   if(hist[1] > hist[2] && hist[2] > hist[3] && hist[3] < 0)
      return true;
   
   // Or histogram crossed from negative to positive (momentum shift)
   if(hist[1] > 0 && hist[2] < 0)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Bearish Volume Spike: High volume on a down candle               |
//+------------------------------------------------------------------+
bool CheckBearishVolumeSpike(double &vol[], double &close[])
{
   // Calculate average volume
   double avgVol = 0;
   for(int v = 2; v < Volume_Average_Periods + 2; v++)
      avgVol += vol[v];
   avgVol /= Volume_Average_Periods;
   
   if(avgVol <= 0) return false;
   
   // Current candle is a down candle with volume spike
   if(close[1] < close[2] && vol[1] >= avgVol * Volume_Spike_Multiplier)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Bullish Volume Spike: High volume on an up candle                |
//+------------------------------------------------------------------+
bool CheckBullishVolumeSpike(double &vol[], double &close[])
{
   // Calculate average volume
   double avgVol = 0;
   for(int v = 2; v < Volume_Average_Periods + 2; v++)
      avgVol += vol[v];
   avgVol /= Volume_Average_Periods;
   
   if(avgVol <= 0) return false;
   
   // Current candle is an up candle with volume spike
   if(close[1] > close[2] && vol[1] >= avgVol * Volume_Spike_Multiplier)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| ADX Trend Exhaustion: ADX dropping from strong to weak           |
//+------------------------------------------------------------------+
bool CheckADXTrendExhaustion(double &adx[])
{
   // ADX was above trend threshold (strong trend) but now below weak threshold
   // Check if ADX dropped from above 25 to below 20 within recent bars
   bool wasStrong = false;
   for(int a = 3; a < 8; a++)
   {
      if(adx[a] >= ADX_Trend_Threshold)
      {
         wasStrong = true;
         break;
      }
   }
   
   if(wasStrong && adx[1] < ADX_Weak_Threshold)
      return true;
   
   // Also trigger if ADX is declining rapidly (3 consecutive lower values from high level)
   if(adx[1] < adx[2] && adx[2] < adx[3] && adx[3] >= ADX_Trend_Threshold)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Manage Basket Trailing (Same-Side)                               |
//+------------------------------------------------------------------+
void ManageBasketTrailing()
{
   // Buy basket trailing
   if(totalBuys > 0)
   {
      if(basketBuyTrail == 0 && buyProfitPips >= Basket_Lock_Pips)
      {
         basketBuyTrail = buyProfitPips - Basket_Trail_Step;
         Print("BASKET TRAIL: Buy basket started at ", DoubleToString(buyProfitPips, 1), " pips");
      }
      
      if(basketBuyTrail > 0)
      {
         if(buyProfitPips > basketBuyTrail + Basket_Trail_Step)
            basketBuyTrail = buyProfitPips - Basket_Trail_Step;
         
         if(buyProfitPips <= basketBuyTrail)
         {
            Print("BASKET TRAIL: Buy basket CLOSED. Pips: ", DoubleToString(buyProfitPips, 1));
            CloseAllBuys("BasketTrail");
            basketBuyTrail = 0;
         }
      }
   }
   else
   {
      basketBuyTrail = 0;
   }
   
   // Sell basket trailing
   if(totalSells > 0)
   {
      if(basketSellTrail == 0 && sellProfitPips >= Basket_Lock_Pips)
      {
         basketSellTrail = sellProfitPips - Basket_Trail_Step;
         Print("BASKET TRAIL: Sell basket started at ", DoubleToString(sellProfitPips, 1), " pips");
      }
      
      if(basketSellTrail > 0)
      {
         if(sellProfitPips > basketSellTrail + Basket_Trail_Step)
            basketSellTrail = sellProfitPips - Basket_Trail_Step;
         
         if(sellProfitPips <= basketSellTrail)
         {
            Print("BASKET TRAIL: Sell basket CLOSED. Pips: ", DoubleToString(sellProfitPips, 1));
            CloseAllSells("BasketTrail");
            basketSellTrail = 0;
         }
      }
   }
   else
   {
      basketSellTrail = 0;
   }
}

//+------------------------------------------------------------------+
//| Check Entry Signal                                                |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   // Get EMA values
   double emaHTF[];
   double emaCTF[];
   ArraySetAsSeries(emaHTF, true);
   ArraySetAsSeries(emaCTF, true);
   
   if(CopyBuffer(handleEMA_HTF, 0, 0, 3, emaHTF) < 3) return;
   if(CopyBuffer(handleEMA_CTF, 0, 0, 3, emaCTF) < 3) return;
   
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Determine trend direction from HTF EMA
   bool htfBullish = (bid > emaHTF[0]);
   bool htfBearish = (bid < emaHTF[0]);
   
   // Check CTF EMA distance
   double ctfDistance = MathAbs(bid - emaCTF[0]) / _Point;
   bool farEnough = (ctfDistance >= Min_EMA_Distance);
   
   // Check CTF price position
   bool ctfBullish = (bid > emaCTF[0]);
   bool ctfBearish = (bid < emaCTF[0]);
   
   // BUY conditions: HTF bullish + CTF bullish + distance OK + pattern
   if(htfBullish && ctfBullish && farEnough)
   {
      int bullPattern = DetectBullishPattern();
      if(bullPattern > 0)
      {
         if(CanOpenTrade(ORDER_TYPE_BUY))
         {
            double lots = CalculateLotSize();
            double sl = Use_StopLoss ? (ask - StopLoss_Pips * _Point) : 0;
            
            if(trade.Buy(lots, _Symbol, ask, sl, 0, EA_Comment))
               Print("BUY opened: ", DoubleToString(lots, 2), " lots | Pattern: ", bullPattern);
         }
      }
   }
   
   // SELL conditions: HTF bearish + CTF bearish + distance OK + pattern
   if(htfBearish && ctfBearish && farEnough)
   {
      int bearPattern = DetectBearishPattern();
      if(bearPattern > 0)
      {
         if(CanOpenTrade(ORDER_TYPE_SELL))
         {
            double lots = CalculateLotSize();
            double sl = Use_StopLoss ? (bid + StopLoss_Pips * _Point) : 0;
            
            if(trade.Sell(lots, _Symbol, bid, sl, 0, EA_Comment))
               Print("SELL opened: ", DoubleToString(lots, 2), " lots | Pattern: ", bearPattern);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Can Open Trade (distance check)                                  |
//+------------------------------------------------------------------+
bool CanOpenTrade(ENUM_ORDER_TYPE type)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != Magic_Number) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      
      if(type == ORDER_TYPE_BUY && posInfo.PositionType() == POSITION_TYPE_BUY)
      {
         double dist = MathAbs(bid - posInfo.PriceOpen()) / _Point;
         if(dist < Min_Trade_Distance)
            return false;
      }
      
      if(type == ORDER_TYPE_SELL && posInfo.PositionType() == POSITION_TYPE_SELL)
      {
         double dist = MathAbs(bid - posInfo.PriceOpen()) / _Point;
         if(dist < Min_Trade_Distance)
            return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(Manual_LotSize > 0)
      return MathMin(Manual_LotSize, Max_LotSize);
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * (Risk_Percent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue <= 0 || tickSize <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   double slDistance = StopLoss_Pips * _Point;
   double lots = riskAmount / ((slDistance / tickSize) * tickValue);
   
   // Normalize
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, MathMin(maxLot, Max_LotSize));
   
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Detect Bullish Candlestick/Chart Patterns                        |
//+------------------------------------------------------------------+
int DetectBullishPattern()
{
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(_Symbol, Trade_Timeframe, 0, 10, open) < 10) return 0;
   if(CopyHigh(_Symbol, Trade_Timeframe, 0, 10, high) < 10) return 0;
   if(CopyLow(_Symbol, Trade_Timeframe, 0, 10, low) < 10) return 0;
   if(CopyClose(_Symbol, Trade_Timeframe, 0, 10, close) < 10) return 0;
   
   double body1 = MathAbs(close[1] - open[1]);
   double range1 = high[1] - low[1];
   double body2 = MathAbs(close[2] - open[2]);
   double range2 = high[2] - low[2];
   
   if(range1 == 0) return 0;
   
   // Hammer
   if(Use_Hammer)
   {
      double lowerShadow = MathMin(open[1], close[1]) - low[1];
      double upperShadow = high[1] - MathMax(open[1], close[1]);
      if(lowerShadow > body1 * 2 && upperShadow < body1 * 0.3 && close[1] > open[1])
         return 1;
   }
   
   // Inverted Hammer
   if(Use_InvHammer)
   {
      double lowerShadow = MathMin(open[1], close[1]) - low[1];
      double upperShadow = high[1] - MathMax(open[1], close[1]);
      if(upperShadow > body1 * 2 && lowerShadow < body1 * 0.3 && close[2] < open[2])
         return 2;
   }
   
   // Bullish Engulfing
   if(Use_BullEngulf)
   {
      if(close[2] < open[2] && close[1] > open[1] && 
         close[1] > open[2] && open[1] < close[2])
         return 3;
   }
   
   // Piercing Line
   if(Use_PiercingLine)
   {
      if(close[2] < open[2] && close[1] > open[1] &&
         open[1] < low[2] && close[1] > (open[2] + close[2]) / 2.0)
         return 4;
   }
   
   // Morning Star
   if(Use_MorningStar)
   {
      double body3 = MathAbs(close[3] - open[3]);
      if(close[3] < open[3] && body2 < body3 * 0.3 && close[1] > open[1] &&
         close[1] > (open[3] + close[3]) / 2.0)
         return 5;
   }
   
   // Three White Soldiers
   if(Use_ThreeWhite)
   {
      if(close[1] > open[1] && close[2] > open[2] && close[3] > open[3] &&
         close[1] > close[2] && close[2] > close[3])
         return 6;
   }
   
   // Bullish Harami
   if(Use_BullHarami)
   {
      if(close[2] < open[2] && close[1] > open[1] &&
         high[1] < open[2] && low[1] > close[2])
         return 7;
   }
   
   // Doji (at support)
   if(Use_Doji)
   {
      if(body1 < range1 * 0.1 && close[2] < open[2])
         return 8;
   }
   
   // Double Bottom
   if(Use_DoubleBottom)
   {
      if(IsDoubleBottom(low, close, high))
         return 9;
   }
   
   // Inverse Head & Shoulders
   if(Use_InvHeadShould)
   {
      if(IsInvHeadShoulders(low, high, close))
         return 10;
   }
   
   // Bull Flag
   if(Use_BullFlag)
   {
      if(IsBullFlag(close, open, high, low))
         return 11;
   }
   
   // Falling Wedge (Bullish)
   if(Use_FallingWedge)
   {
      if(IsFallingWedge(high, low))
         return 12;
   }
   
   // Ascending Triangle (Bullish)
   if(Use_BullTriangle)
   {
      if(IsBullTriangle(high, low))
         return 13;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Detect Bearish Candlestick/Chart Patterns                        |
//+------------------------------------------------------------------+
int DetectBearishPattern()
{
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(_Symbol, Trade_Timeframe, 0, 10, open) < 10) return 0;
   if(CopyHigh(_Symbol, Trade_Timeframe, 0, 10, high) < 10) return 0;
   if(CopyLow(_Symbol, Trade_Timeframe, 0, 10, low) < 10) return 0;
   if(CopyClose(_Symbol, Trade_Timeframe, 0, 10, close) < 10) return 0;
   
   double body1 = MathAbs(close[1] - open[1]);
   double range1 = high[1] - low[1];
   double body2 = MathAbs(close[2] - open[2]);
   double range2 = high[2] - low[2];
   
   if(range1 == 0) return 0;
   
   // Shooting Star
   if(Use_ShootingStar)
   {
      double upperShadow = high[1] - MathMax(open[1], close[1]);
      double lowerShadow = MathMin(open[1], close[1]) - low[1];
      if(upperShadow > body1 * 2 && lowerShadow < body1 * 0.3 && close[1] < open[1])
         return 1;
   }
   
   // Bearish Engulfing
   if(Use_BearEngulf)
   {
      if(close[2] > open[2] && close[1] < open[1] && 
         close[1] < open[2] && open[1] > close[2])
         return 2;
   }
   
   // Evening Star
   if(Use_EveningStar)
   {
      double body3 = MathAbs(close[3] - open[3]);
      if(close[3] > open[3] && body2 < body3 * 0.3 && close[1] < open[1] &&
         close[1] < (open[3] + close[3]) / 2.0)
         return 3;
   }
   
   // Three Black Crows
   if(Use_ThreeBlack)
   {
      if(close[1] < open[1] && close[2] < open[2] && close[3] < open[3] &&
         close[1] < close[2] && close[2] < close[3])
         return 4;
   }
   
   // Dark Cloud Cover
   if(Use_DarkCloud)
   {
      if(close[2] > open[2] && close[1] < open[1] &&
         open[1] > high[2] && close[1] < (open[2] + close[2]) / 2.0)
         return 5;
   }
   
   // Bearish Harami
   if(Use_BearHarami)
   {
      if(close[2] > open[2] && close[1] < open[1] &&
         high[1] < close[2] && low[1] > open[2])
         return 6;
   }
   
   // Hanging Man
   if(Use_HangingMan)
   {
      double lowerShadow = MathMin(open[1], close[1]) - low[1];
      double upperShadow = high[1] - MathMax(open[1], close[1]);
      if(lowerShadow > body1 * 2 && upperShadow < body1 * 0.3 && close[1] < open[1])
         return 7;
   }
   
   // Doji (at resistance)
   if(Use_Doji)
   {
      if(body1 < range1 * 0.1 && close[2] > open[2])
         return 8;
   }
   
   // Double Top
   if(Use_DoubleTop)
   {
      if(IsDoubleTop(high, close, low))
         return 9;
   }
   
   // Head & Shoulders
   if(Use_HeadShoulders)
   {
      if(IsHeadShoulders(high, low, close))
         return 10;
   }
   
   // Bear Flag
   if(Use_BearFlag)
   {
      if(IsBearFlag(close, open, high, low))
         return 11;
   }
   
   // Rising Wedge (Bearish)
   if(Use_RisingWedge)
   {
      if(IsRisingWedge(high, low))
         return 12;
   }
   
   // Descending Triangle (Bearish)
   if(Use_BearTriangle)
   {
      if(IsBearTriangle(high, low))
         return 13;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Chart Pattern Detection Helpers                                   |
//+------------------------------------------------------------------+
bool IsDoubleBottom(double &low[], double &close[], double &high[])
{
   // Simple: two recent lows within tolerance, with a higher low between
   double tol = (high[1] - low[1]) * 0.5;
   if(MathAbs(low[1] - low[5]) < tol && low[3] > low[1] + tol)
      return true;
   return false;
}

bool IsDoubleTop(double &high[], double &close[], double &low[])
{
   double tol = (high[1] - low[1]) * 0.5;
   if(MathAbs(high[1] - high[5]) < tol && high[3] < high[1] - tol)
      return true;
   return false;
}

bool IsHeadShoulders(double &high[], double &low[], double &close[])
{
   // Left shoulder < head, right shoulder < head, shoulders roughly equal
   if(high[2] > high[4] && high[2] > high[6] && 
      MathAbs(high[4] - high[6]) < (high[2] - high[4]) * 0.5)
      return true;
   return false;
}

bool IsInvHeadShoulders(double &low[], double &high[], double &close[])
{
   if(low[2] < low[4] && low[2] < low[6] && 
      MathAbs(low[4] - low[6]) < (low[4] - low[2]) * 0.5)
      return true;
   return false;
}

bool IsBullFlag(double &close[], double &open[], double &high[], double &low[])
{
   // Strong up move followed by slight pullback
   double move = close[5] - close[9];
   double pullback = close[5] - close[1];
   if(move > 0 && pullback > 0 && pullback < move * 0.38 && close[1] > open[1])
      return true;
   return false;
}

bool IsBearFlag(double &close[], double &open[], double &high[], double &low[])
{
   // Strong down move followed by slight pullback up
   double move = close[9] - close[5];
   double pullback = close[1] - close[5];
   if(move > 0 && pullback > 0 && pullback < move * 0.38 && close[1] < open[1])
      return true;
   return false;
}

bool IsRisingWedge(double &high[], double &low[])
{
   // Highs rising slower than lows (converging)
   double highSlope = high[1] - high[5];
   double lowSlope = low[1] - low[5];
   if(highSlope > 0 && lowSlope > 0 && lowSlope > highSlope)
      return true;
   return false;
}

bool IsFallingWedge(double &high[], double &low[])
{
   // Lows falling slower than highs (converging down)
   double highSlope = high[5] - high[1];
   double lowSlope = low[5] - low[1];
   if(highSlope > 0 && lowSlope > 0 && lowSlope > highSlope)
      return true;
   return false;
}

bool IsBullTriangle(double &high[], double &low[])
{
   // Flat top, rising lows
   double tol = (high[1] - low[1]) * 0.3;
   if(MathAbs(high[1] - high[5]) < tol && low[1] > low[5])
      return true;
   return false;
}

bool IsBearTriangle(double &high[], double &low[])
{
   // Flat bottom, falling highs
   double tol = (high[1] - low[1]) * 0.3;
   if(MathAbs(low[1] - low[5]) < tol && high[1] < high[5])
      return true;
   return false;
}

//+------------------------------------------------------------------+
//| Close All Positions                                               |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   Print("CLOSING ALL POSITIONS - Reason: ", reason);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != Magic_Number) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      
      trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Close All Buys                                                    |
//+------------------------------------------------------------------+
void CloseAllBuys(string reason)
{
   Print("CLOSING ALL BUYS - Reason: ", reason);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != Magic_Number) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.PositionType() != POSITION_TYPE_BUY) continue;
      
      trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Close All Sells                                                   |
//+------------------------------------------------------------------+
void CloseAllSells(string reason)
{
   Print("CLOSING ALL SELLS - Reason: ", reason);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Magic() != Magic_Number) continue;
      if(posInfo.Symbol() != _Symbol) continue;
      if(posInfo.PositionType() != POSITION_TYPE_SELL) continue;
      
      trade.PositionClose(posInfo.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int y = Dashboard_Y;
   int lineHeight = 20;
   color textColor = clrWhite;
   
   // Background panel
   string bgName = dashboardPrefix + "BG";
   if(ObjectFind(0, bgName) < 0)
   {
      ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, Dashboard_X);
      ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, Dashboard_Y - 10);
      ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 320);
      ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 380);
      ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, C'20,20,35');
      ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, bgName, OBJPROP_COLOR, clrDarkSlateGray);
   }
   
   // Title
   CreateLabel(dashboardPrefix + "Title", Dashboard_X + 10, y, "GaganEA v2.10", clrGold, 11);
   y += lineHeight + 5;
   
   // Account Info
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double ddPct = balance > 0 ? ((balance - equity) / balance) * 100.0 : 0;
   
   CreateLabel(dashboardPrefix + "Balance", Dashboard_X + 10, y, 
               "Balance: $" + DoubleToString(balance, 2), clrWhite, 9);
   y += lineHeight;
   
   CreateLabel(dashboardPrefix + "Equity", Dashboard_X + 10, y, 
               "Equity: $" + DoubleToString(equity, 2), clrWhite, 9);
   y += lineHeight;
   
   color ddColor = (ddPct > 3.0) ? clrRed : (ddPct > 1.5) ? clrOrange : clrLime;
   CreateLabel(dashboardPrefix + "DD", Dashboard_X + 10, y, 
               "Drawdown: " + DoubleToString(ddPct, 2) + "%", ddColor, 9);
   y += lineHeight + 5;
   
   // Position Info
   CreateLabel(dashboardPrefix + "Buys", Dashboard_X + 10, y, 
               "Buys: " + IntegerToString(totalBuys) + " | Pips: " + DoubleToString(buyProfitPips, 1), 
               totalBuys > 0 ? clrDodgerBlue : clrGray, 9);
   y += lineHeight;
   
   CreateLabel(dashboardPrefix + "Sells", Dashboard_X + 10, y, 
               "Sells: " + IntegerToString(totalSells) + " | Pips: " + DoubleToString(sellProfitPips, 1), 
               totalSells > 0 ? clrTomato : clrGray, 9);
   y += lineHeight + 5;
   
   // Trend Info
   double emaHTF[];
   ArraySetAsSeries(emaHTF, true);
   string trendStr = "---";
   color trendColor = clrGray;
   if(CopyBuffer(handleEMA_HTF, 0, 0, 1, emaHTF) >= 1)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid > emaHTF[0]) { trendStr = "BULLISH"; trendColor = clrLime; }
      else { trendStr = "BEARISH"; trendColor = clrRed; }
   }
   CreateLabel(dashboardPrefix + "Trend", Dashboard_X + 10, y, 
               "HTF Trend: " + trendStr, trendColor, 9);
   y += lineHeight;
   
   // Spread
   double spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   CreateLabel(dashboardPrefix + "Spread", Dashboard_X + 10, y, 
               "Spread: " + DoubleToString(spread, 0) + " pts", clrWhite, 9);
   y += lineHeight + 5;
   
   // AMA Status
   string amaStatus = Use_AMA_Exit ? "Active" : "OFF";
   color amaColor = Use_AMA_Exit ? clrLime : clrGray;
   CreateLabel(dashboardPrefix + "AMA", Dashboard_X + 10, y, 
               "AMA Exit: " + amaStatus + " (Flips B:" + IntegerToString(amaFlipCountBuy) + 
               " S:" + IntegerToString(amaFlipCountSell) + ")", amaColor, 9);
   y += lineHeight;
   
   // Reversal Detection Status
   color revColor;
   int maxSignals = MathMax(lastReversalBuySignals, lastReversalSellSignals);
   if(!Use_Reversal_Exit)
   {
      revColor = clrGray;
      lastReversalStatus = "OFF";
   }
   else if(maxSignals >= Reversal_Min_Confirmations)
      revColor = clrRed;
   else if(maxSignals >= 1)
      revColor = clrOrange;
   else
      revColor = clrLime;
   
   CreateLabel(dashboardPrefix + "Reversal", Dashboard_X + 10, y, 
               "Reversal: " + lastReversalStatus, revColor, 9);
   y += lineHeight;
   
   // Basket Trail Status
   string basketStatus = "";
   if(basketBuyTrail > 0) basketStatus += "B:" + DoubleToString(basketBuyTrail, 1) + " ";
   if(basketSellTrail > 0) basketStatus += "S:" + DoubleToString(basketSellTrail, 1);
   if(basketStatus == "") basketStatus = "Inactive";
   
   CreateLabel(dashboardPrefix + "Basket", Dashboard_X + 10, y, 
               "Basket Trail: " + basketStatus, 
               (basketBuyTrail > 0 || basketSellTrail > 0) ? clrYellow : clrGray, 9);
   y += lineHeight;
   
   // Master EP Status
   string masterStatus = "";
   if(masterBuyActive) masterStatus += "B:Active ";
   if(masterSellActive) masterStatus += "S:Active";
   if(masterStatus == "") masterStatus = Use_Master_EP ? "Monitoring" : "OFF";
   
   CreateLabel(dashboardPrefix + "Master", Dashboard_X + 10, y, 
               "Master EP: " + masterStatus, 
               (masterBuyActive || masterSellActive) ? clrOrange : clrGray, 9);
   y += lineHeight + 5;
   
   // Time
   CreateLabel(dashboardPrefix + "Time", Dashboard_X + 10, y, 
               "Server: " + TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), clrGray, 8);
}

//+------------------------------------------------------------------+
//| Create/Update Dashboard Label                                     |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}
//+------------------------------------------------------------------+

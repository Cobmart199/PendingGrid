//+------------------------------------------------------------------+
//|                                                  PendingGrid.mq4 |
//|                                               mt4programming.com |
//|                                    http://www.mt4programming.com |
//+------------------------------------------------------------------+
#property copyright "mt4programming.com"
#property link      "http://www.mt4programming.com"
//Owner Cyril Balonwu
//version 1.0 by Alex Pyrkov March 18, 2013
//version 1.1 by Alex Pyrkov March 25, 2013
//version 1.2 by Alex Pyrkov May 25, 2013

#include <stderror.mqh>
#include <stdlib.mqh>
#define name "PendingGrid v 1.2"

extern string comment=name;
extern bool EntryLong=true;
extern bool EntryShort=true;
extern double  order_amount_lots=0.01;
extern int MagicNumber=17181930;
extern int slippage=3;
extern int line_interval_points=25;
extern int maxNumberOfPending=5;
extern double pauseMarginPercent=20.0;
extern double max_lot_size=0.32;

extern int  stoploss_points=100;
extern int  takeprofit_points=5;

//order repetition
int repeat=30;//new
int sleep_interval=1000;//new
int lastOrderSide=1; // 0=long, 1=short
int pairSize=1; // number of paired units to maintain per side

int init()
{
   return(0);
}
  
int deinit()
{
   return(0);
}

int start()
{
   double buytar=BottomMajorLine(Bid);
   double selltar=UpperMajorLine(Bid);
   
   // Display margin info for debugging
   // DisplayOandaMarginUsage();
   // Dump current orders for debugging pending->market behavior
   // DumpOrders();
   
   // Debug logging disabled to reduce log volume
   // if(!EntryShort) Print("DEBUG: EntryShort is false");
   // if(IsPriceOccupied(selltar)) Print("DEBUG: Price occupied at ", selltar);
   // if(!NoLongTrades()) Print("DEBUG: Long trades exist");
   // if(IsMarginLimitReached()) Print("DEBUG: Margin limit reached");
   
   bool allowLong = EntryLong && !IsPriceOccupied(buytar) && !IsMarginLimitReached();
   bool allowShort = EntryShort && !IsPriceOccupied(selltar) && !IsMarginLimitReached();
   int pendingLong = CountPendingOrdersBySide(true);
   int pendingShort = CountPendingOrdersBySide(false);
   double lotToPlaceLong = order_amount_lots;
   double lotToPlaceShort = order_amount_lots;
   if(maxNumberOfPending > 1)
   {
      lotToPlaceLong = order_amount_lots * MathPow(2.0, pendingLong + 1);
      lotToPlaceShort = order_amount_lots * MathPow(2.0, pendingShort + 1);
      if(lotToPlaceLong > max_lot_size) lotToPlaceLong = max_lot_size;
      if(lotToPlaceShort > max_lot_size) lotToPlaceShort = max_lot_size;
   }
   // Debug logging disabled to reduce log volume

   if(allowLong || allowShort)
   {
      if(allowLong && allowShort)
      {
         EnterLongLimit(buytar, lotToPlaceLong);
         EnterShortLimit(selltar, lotToPlaceShort);
      }
      else if(allowLong)
      {
         EnterLongLimit(buytar, lotToPlaceLong);
         lastOrderSide = 0;
      }
      else if(allowShort)
      {
         EnterShortLimit(selltar, lotToPlaceShort);
         lastOrderSide = 1;
      }
   }
   TrackPendingChanges();
   CutFarthest(Bid);
   return(0);
}

// --- pending tracker ---
int trackedPendingTickets[200];
int trackedPendingCount=0;

void TrackPendingChanges()
{
   // Build current pending ticket list
   int curr[200];
   int currCount=0;
   int total=OrdersTotal();
   for(int i=0;i<total;i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      int t=OrderType();
      if(t==OP_BUYLIMIT || t==OP_SELLLIMIT || t==OP_BUYSTOP || t==OP_SELLSTOP)
      {
         curr[currCount++]=OrderTicket();
         if(currCount>=ArraySize(curr)) break;
      }
   }

   // Compare trackedPendingTickets -> if a previously tracked ticket is missing, log it
   for(int j=0;j<trackedPendingCount;j++)
   {
      int ticket=trackedPendingTickets[j];
      bool found=false;
      for(int k=0;k<currCount;k++) if(curr[k]==ticket) { found=true; break; }
      if(!found)
      {
         // Print("DEBUG: Pending ticket removed (likely executed/deleted): ", ticket);
      }
   }

   // Save current as tracked
   ArrayInitialize(trackedPendingTickets, -1);
   trackedPendingCount = 0;
   for(int m=0;m<currCount;m++)
   {
      trackedPendingTickets[trackedPendingCount++] = curr[m];
      if(trackedPendingCount>=ArraySize(trackedPendingTickets)) break;
   }
}


double CountLotsBySide(bool longSide)
{
   double totalLots=0.0;
   int total=OrdersTotal();
   for(int i=0;i<total;i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;

      int type = OrderType();
      if(longSide)
      {
         if(type==OP_BUY || type==OP_BUYLIMIT || type==OP_BUYSTOP)
            totalLots += OrderLots();
      }
      else
      {
         if(type==OP_SELL || type==OP_SELLLIMIT || type==OP_SELLSTOP)
            totalLots += OrderLots();
      }
   }
   return(totalLots);
}

int CountOrdersBySide(bool longSide)
{
   int count=0;
   int total=OrdersTotal();
   for(int i=0;i<total;i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(longSide)
      {
         if(type==OP_BUY || type==OP_BUYLIMIT || type==OP_BUYSTOP)
            count++;
      }
      else
      {
         if(type==OP_SELL || type==OP_SELLLIMIT || type==OP_SELLSTOP)
            count++;
      }
   }
   return(count);
}

bool NoLongTrades()
{
   int total=OrdersTotal();
   for(int n=0;n<total;n++)
   {
      if(OrderSelect(n,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderType()==OP_BUY) 
      {
         return (false);
      }
   }
   return (true);
}

bool NoShortTrades()
{
   int total=OrdersTotal();
   for(int n=0;n<total;n++)
   {
      if(OrderSelect(n,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderType()==OP_SELL)
      {
         return (false);
      }
   }
   return (true);
}

void PrintError(string pair)
{
   int err=GetLastError();
   Print("Error# ",err," ",ErrorDescription(err)," for ",pair);
}

bool IsEqual(double val1, double val2,int acc=1)
{
   return (MathAbs(val1-val2)<=(acc*Point));
}

// Calculate actual used margin percentage against equity
double GetMarginPercent()
{
   double usedMargin = AccountMargin();
   double equity = AccountEquity();
   
   if(equity <= 0 || usedMargin <= 0) return 0;
   
   return (usedMargin / equity) * 100;
}

bool IsMarginLimitReached()
{
   double marginPercent = GetMarginPercent();
   
   if(marginPercent >= pauseMarginPercent)
   {
      Print("Margin limit reached (", marginPercent, "%). No new orders will be placed.");
      return true;
   }
   return false;
}

// Calculate net units in Oanda-style position units (open market positions only)
double GetNetUnits()
{
   double netUnits = 0.0;
   double contractSize = MarketInfo(Symbol(), MODE_LOTSIZE);
   if(contractSize <= 0) contractSize = 100000;

   int total = OrdersTotal();
   for(int i=0; i<total; i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;

      if(OrderType()==OP_BUY)
         netUnits += OrderLots() * contractSize;
      else if(OrderType()==OP_SELL)
         netUnits -= OrderLots() * contractSize;
   }
   return(netUnits);
}

// Display margin usage information for debugging
void DisplayOandaMarginUsage()
{
   double marginPercent = GetMarginPercent();
   double marginUsed = AccountMargin();
   double marginAvailable = AccountFreeMargin();
   double accountBalance = AccountBalance();
   double accountEquity = AccountEquity();
   double netUnits = GetNetUnits();
   
   // Print to Journal/Experts tab
   Print("Margin Used: " + DoubleToStr(marginUsed, 2) + 
         " | Margin Available: " + DoubleToStr(marginAvailable, 2) + 
         " | Balance: " + DoubleToStr(accountBalance, 2) +
         " | Equity: " + DoubleToStr(accountEquity, 2) +
         " | Margin %: " + DoubleToStr(marginPercent, 2) + "%" +
         " | Net Units: " + DoubleToStr(netUnits, 2));
}

// Convert input pips into actual price distance for the current symbol
int GetPipMultiplier()
{
   return ((Digits == 3 || Digits == 5) ? 10 : 1);
}

double GetPipSize()
{
   return Point * GetPipMultiplier();
}

int GetStopLossPoints()
{
   return stoploss_points;
}


double BottomMajorLine(double pr)
{
   int ipr=pr/Point;
   int tmp=ipr/line_interval_points;
   return (tmp*line_interval_points*Point);
}

double UpperMajorLine(double pr)
{
   return (BottomMajorLine(pr)+line_interval_points*Point);
}



void EnterLongLimit(double target, double lotSize)
{
  int res=-1;
  double pip = GetPipSize();
  double tp=target+takeprofit_points*pip;
  if(IsEqual(takeprofit_points,0) || takeprofit_points<0) tp=0;
   if(lotSize <= 0) lotSize = order_amount_lots;
  for(int i=0;(i<repeat) && (res<0);i++)
  {
      RefreshRates();

      int currentSL = GetStopLossPoints();
      double sl=target-currentSL*pip;
      if(IsEqual(currentSL,0) || currentSL<0) sl=0;

      res=OrderSend(Symbol(),OP_BUYLIMIT,lotSize,target,slippage,sl,tp,comment,MagicNumber,0,Green);

      if(res<0)
      {
        PrintError(Symbol());
        Sleep(sleep_interval);
      }
      else
      {
             // Log the placed pending order
             if(OrderSelect(res, SELECT_BY_TICKET) )
             {
                  // Print("DEBUG: Placed pending BUYLIMIT ticket=", res,
                  //       " type=", OrderType(), " price=", DoubleToStr(OrderOpenPrice(), Digits),
                  //       " lots=", DoubleToStr(OrderLots(),2), " magic=", OrderMagicNumber());
             }
         break;
      }
  }
}

void EnterShortLimit(double target, double lotSize)
{
  int res=-1;
  double pip = GetPipSize();
  double tp=target-takeprofit_points*pip;
  if(IsEqual(takeprofit_points,0) || takeprofit_points<0) tp=0;
   if(lotSize <= 0) lotSize = order_amount_lots;
  for(int i=0;(i<repeat) && (res<0);i++)
  {
      RefreshRates();

      int currentSL = GetStopLossPoints();
      double sl=target+currentSL*pip;
      if(IsEqual(currentSL,0) || currentSL<0) sl=0;

      res=OrderSend(Symbol(),OP_SELLLIMIT,lotSize,target,slippage,sl,tp,comment,MagicNumber,0,Red);
      if(res<0)
      {
        PrintError(Symbol());
        Sleep(sleep_interval);
      }
      else
      {
         // Log the placed pending order
         if(OrderSelect(res, SELECT_BY_TICKET) )
         {
            // Print("DEBUG: Placed pending SELLLIMIT ticket=", res,
            //       " type=", OrderType(), " price=", DoubleToStr(OrderOpenPrice(), Digits),
            //       " lots=", DoubleToStr(OrderLots(),2), " magic=", OrderMagicNumber());
         }
         break;
      }
   }
}

// Helper: print current orders (ticket, type, lots, price, magic)
void DumpOrders()
{
   int total=OrdersTotal();
   // Print("DEBUG: DumpOrders - total=", total);
   for(int i=0;i<total;i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      string ttype = "UNKNOWN";
      int type = OrderType();
      if(type==OP_BUY) ttype="BUY";
      else if(type==OP_SELL) ttype="SELL";
      else if(type==OP_BUYLIMIT) ttype="BUYLIMIT";
      else if(type==OP_SELLLIMIT) ttype="SELLLIMIT";
      else if(type==OP_BUYSTOP) ttype="BUYSTOP";
      else if(type==OP_SELLSTOP) ttype="SELLSTOP";

      // Print("DEBUG: Order #", i, " ticket=", OrderTicket(), " type=", ttype,
      //       " price=", DoubleToStr(OrderOpenPrice(), Digits),
      //       " lots=", DoubleToStr(OrderLots(),2), " magic=", OrderMagicNumber());
   }
}

bool IsPriceOccupied(double pr)
{
   int total=OrdersTotal();
   for(int n=0;n<total;n++)
   {
      if(OrderSelect(n,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      int type = OrderType();
      // Only consider pending orders as occupying a pending price.
      if(type==OP_BUYLIMIT || type==OP_SELLLIMIT || type==OP_BUYSTOP || type==OP_SELLSTOP)
      {
         if(IsEqual(OrderOpenPrice(),pr))
         {
            return (true);
         }
      }
   }
   return (false);
}

int CountPendingOrders()
{
   int count=0;
   int total=OrdersTotal();
   for(int i=0;i<total;i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      int type = OrderType();
      if(type==OP_BUYLIMIT || type==OP_BUYSTOP || type==OP_SELLLIMIT || type==OP_SELLSTOP)
         count++;
   }
   return(count);
}

int CountPendingOrdersBySide(bool longSide)
{
   int count=0;
   int total=OrdersTotal();
   for(int i=0;i<total;i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      int type = OrderType();
      if(longSide)
      {
         if(type==OP_BUYLIMIT || type==OP_BUYSTOP)
            count++;
      }
      else
      {
         if(type==OP_SELLLIMIT || type==OP_SELLSTOP)
            count++;
      }
   }
   return(count);
}

void CutFarthest(double pr)
{
   int counter=0;
   double dist=-1;
   int ticket=-1;
   int total=OrdersTotal();
   for(int i=0;i<total;i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderType()==OP_BUYSTOP || OrderType()==OP_BUYLIMIT || OrderType()==OP_SELLLIMIT || OrderType()==OP_SELLSTOP) 
      {
         counter++;
         double currdist=MathAbs(OrderOpenPrice()-pr);
         if(currdist>dist)
         {
            dist=currdist;
            ticket=OrderTicket();
         }
      }
   }
   if(counter>maxNumberOfPending)
   {
      if(ticket>=0)
      {
         int count=0;
         while(!OrderDelete(ticket))
         {
            count++;
            if(count<=repeat)
            {
               Sleep(sleep_interval);
            }
            else
            {
               PrintError(Symbol());
               break;
            }
         }
      }
   }
}

void DeleteLongPending()
{
   //close pending, if any 
   int total=OrdersTotal();
   int toDelete[50];
   ArrayInitialize(toDelete,-1);
   int j=0;
   for(int i=0;i<total;i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      if(OrderType()==OP_BUYLIMIT) 
      {
         toDelete[j]=OrderTicket();
         j++;
         if(j>=(ArraySize(toDelete)-1)) ArrayResize(toDelete,ArraySize(toDelete)+50);
      }
   }
   int sz=ArraySize(toDelete);
   for(int k=0;k<sz;k++)
   {
      if(toDelete[k]>0)
      {
         int count=0;
         while(!OrderDelete(toDelete[k]))
         {
            count++;
            if(count<=repeat)
            {
               Sleep(sleep_interval);
            }
            else
            {
               PrintError(Symbol());
               break;
            }
         }
      }
   }
}

void DeleteShortPending()
{
   //close pending, if any 
   int total=OrdersTotal();
   int toDelete[50];
   ArrayInitialize(toDelete,-1);
   int j=0;
   for(int i=0;i<total;i++)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)==false) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderCloseTime()!=0) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      if(OrderType()==OP_SELLLIMIT) 
      {
         toDelete[j]=OrderTicket();
         j++;
         if(j>=(ArraySize(toDelete)-1)) ArrayResize(toDelete,ArraySize(toDelete)+50);
      }
   }
   int sz=ArraySize(toDelete);
   for(int k=0;k<sz;k++)
   {
      if(toDelete[k]>0)
      {
         int count=0;
         while(!OrderDelete(toDelete[k]))
         {
            count++;
            if(count<=repeat)
            {
               Sleep(sleep_interval);
            }
            else
            {
               PrintError(Symbol());
               break;
            }
         }
      }
   }
}


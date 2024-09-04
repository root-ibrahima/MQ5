//+------------------------------------------------------------------+
//|                           Suivi_Tendance_Multi_IndicateursV2.mq5 |
//|                                                  Ibrahima DIALLO |
//|                                                                  |
//+------------------------------------------------------------------+

// Variables globales pour la gestion des risques
double initialBalance = 0.0;       // Solde initial au démarrage de l'EA
double maxLossPercentage = 0.05;   // Perte maximale autorisée (5% du solde initial)
double maxLossAmount = 0.0;        // Montant maximal de la perte autorisée
double totalLoss = 0.0;            // Suivi des pertes réalisées

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialisation du capital initial et calcul de la perte maximale autorisée
   initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   maxLossAmount = initialBalance * maxLossPercentage; // 5% du capital initial

   Print("EA démarré avec un solde initial de : ", initialBalance);
   Print("Perte maximale autorisée : ", maxLossAmount);

   // Vérification des indicateurs
   if (!InitializeIndicators())
   {
      Print("Erreur lors de l'initialisation des indicateurs.");
      return(INIT_FAILED);
   }

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Fonction pour initialiser les indicateurs                        |
//+------------------------------------------------------------------+
bool InitializeIndicators()
{
   bool success = true;

   // Initialisation des handles d'indicateurs
   int emaHandle = iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE);
   if (emaHandle == INVALID_HANDLE)
   {
      Print("Erreur lors de l'initialisation de l'EMA");
      success = false;
   }

   int rsiHandle = iRSI(_Symbol, _Period, 14, PRICE_CLOSE);
   if (rsiHandle == INVALID_HANDLE)
   {
      Print("Erreur lors de l'initialisation du RSI");
      success = false;
   }

   int macdHandle = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE);
   if (macdHandle == INVALID_HANDLE)
   {
      Print("Erreur lors de l'initialisation du MACD");
      success = false;
   }

   int atrHandle = iATR(_Symbol, _Period, 14);
   if (atrHandle == INVALID_HANDLE)
   {
      Print("Erreur lors de l'initialisation de l'ATR");
      success = false;
   }

   return success;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Vérifier si la perte maximale est atteinte
   if (CheckMaxLossReached())
   {
      Print("Perte maximale atteinte. Aucun nouveau trade ne sera pris.");
      return; // Arrêter l'exécution si la perte maximale est atteinte
   }

   // Paramètres de la stratégie
   double riskPerTrade = 0.01;       // Risque en pourcentage par trade (1% du capital)
   double rsiOverbought = 70;        // Seuil de surachat RSI
   double rsiOversold = 30;          // Seuil de survente RSI

   // Récupérer les informations du marché
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Calcul des indicateurs techniques
   double emaValue[], rsiValue[], macdMain[], macdSignal[], atrValue[];

   // Récupération des valeurs EMA
   if (CopyBuffer(iMA(_Symbol, _Period, 50, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 1, emaValue) <= 0)
   {
      Print("Erreur lors de la récupération de l'EMA");
      return;
   }

   // Récupération des valeurs RSI
   if (CopyBuffer(iRSI(_Symbol, _Period, 14, PRICE_CLOSE), 0, 0, 1, rsiValue) <= 0)
   {
      Print("Erreur lors de la récupération du RSI");
      return;
   }

   // Récupération des valeurs MACD (Main et Signal)
   if (CopyBuffer(iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE), 0, 0, 1, macdMain) <= 0)
   {
      Print("Erreur lors de la récupération du MACD Main");
      return;
   }

   if (CopyBuffer(iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE), 1, 0, 1, macdSignal) <= 0)
   {
      Print("Erreur lors de la récupération du MACD Signal");
      return;
   }

   // Récupération des valeurs ATR
   if (CopyBuffer(iATR(_Symbol, _Period, 14), 0, 0, 1, atrValue) <= 0)
   {
      Print("Erreur lors de la récupération de l'ATR");
      return;
   }

   // Gestion des positions ouvertes
   int totalPositions = PositionsTotal();
   bool isPositionOpen = false;

   for (int i = 0; i < totalPositions; i++)
   {
      if (PositionSelect(_Symbol))
      {
         isPositionOpen = true;
         break;
      }
   }

   // Conditions d'entrée dans le marché (achat si prix > EMA, RSI < 70, et MACD > Signal)
   if (!isPositionOpen)
   {
      double lot = CalculateLotSize(riskPerTrade, atrValue[0] * 2); // ATR utilisé pour ajuster la taille du SL
      double stopLossPips = atrValue[0] * 2;
      double takeProfitPips = atrValue[0] * 4;

      // Vérification de la marge disponible avant l'envoi de l'ordre
      double marginRequired = lot * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

      if (freeMargin < marginRequired)
      {
         // Réduire la taille du lot jusqu'à ce qu'elle corresponde à la marge disponible
         while (freeMargin < marginRequired && lot > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            lot -= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            marginRequired = lot * SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
         }
         
         Print("Marge insuffisante. Taille de lot ajustée à : ", lot);
         
         // Si la taille de lot ajustée est trop petite, annuler la transaction
         if (lot < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
         {
            Print("Taille de lot après ajustement est trop petite. Annulation de l'ordre.");
            return;
         }
      }

      // Exécuter un achat ou une vente selon les conditions de marché
      if (bid > emaValue[0] && rsiValue[0] < rsiOverbought && macdMain[0] > macdSignal[0]) // Achat
      {
         if (!PlaceOrder(ORDER_TYPE_BUY, lot, ask, bid - stopLossPips * point, bid + takeProfitPips * point))
            Print("Erreur lors de l'envoi de l'ordre d'achat");
      }
      else if (bid < emaValue[0] && rsiValue[0] > rsiOversold && macdMain[0] < macdSignal[0]) // Vente
      {
         if (!PlaceOrder(ORDER_TYPE_SELL, lot, bid, ask + stopLossPips * point, ask - takeProfitPips * point))
            Print("Erreur lors de l'envoi de l'ordre de vente");
      }
   }
}

//+------------------------------------------------------------------+
//| Fonction pour envoyer les ordres de trading                      |
//+------------------------------------------------------------------+
bool PlaceOrder(int orderType, double lot, double price, double stopLoss, double takeProfit)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   // Récupérer la distance minimale entre le prix et les niveaux de SL/TP
   double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * _Point;
   double stopLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   
   Print("Niveau minimal requis pour Stop Loss et Take Profit (stopLevel) : ", stopLevel);
   Print("Niveau de gel (freezeLevel) : ", freezeLevel);
   
   // Ajuster les niveaux de Stop Loss et Take Profit si nécessaire
   if (orderType == ORDER_TYPE_BUY)
   {
      if ((price - stopLoss) < stopLevel || (price - stopLoss) < freezeLevel)
      {
         stopLoss = price - MathMax(stopLevel, freezeLevel);
         Print("Stop Loss ajusté à ", stopLoss, " pour respecter les niveaux minimaux.");
      }
      if ((takeProfit - price) < stopLevel || (takeProfit - price) < freezeLevel)
      {
         takeProfit = price + MathMax(stopLevel, freezeLevel);
         Print("Take Profit ajusté à ", takeProfit, " pour respecter les niveaux minimaux.");
      }
   }
   else if (orderType == ORDER_TYPE_SELL)
   {
      if ((stopLoss - price) < stopLevel || (stopLoss - price) < freezeLevel)
      {
         stopLoss = price + MathMax(stopLevel, freezeLevel);
         Print("Stop Loss ajusté à ", stopLoss, " pour respecter les niveaux minimaux.");
      }
      if ((price - takeProfit) < stopLevel || (price - takeProfit) < freezeLevel || takeProfit == price)
      {
         takeProfit = price - MathMax(stopLevel, freezeLevel);
         Print("Take Profit ajusté à ", takeProfit, " pour respecter les niveaux minimaux.");
      }
   }

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lot;
   request.type = orderType;
   request.price = price;
   request.sl = stopLoss;
   request.tp = takeProfit;
   request.deviation = 2;
   request.magic = 123456;

   if (!OrderSend(request, result))
   {
      int errorCode = GetLastError();
      Print("Erreur lors de l'envoi de l'ordre : ", errorCode);
      
      // Loguer des informations supplémentaires pour déboguer l'erreur
      Print("Détails de l'ordre - Volume: ", lot, ", Prix: ", price, ", SL: ", stopLoss, ", TP: ", takeProfit);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Calcul de la taille du lot en fonction du risque                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPerTrade, double stopLossPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double riskAmount = accountBalance * riskPerTrade; // Risque en fonction du solde du compte

   double pipValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double lotSize = riskAmount / (stopLossPips * pipValue);

   // Ajuster la taille du lot au minimum et aux incréments permis
   lotSize = MathMax(minVolume, MathMin(maxVolume, NormalizeDouble(lotSize, 2)));

   // S'assurer que la taille du lot respecte l'incrément du broker
   lotSize = MathFloor(lotSize / volumeStep) * volumeStep;

   Print("Taille de lot ajustée : ", lotSize);
   return lotSize;
}

//+------------------------------------------------------------------+
//| Fonction pour vérifier si la perte maximale est atteinte          |
//+------------------------------------------------------------------+
bool CheckMaxLossReached()
{
   // Calculer le total des pertes réalisées
   double realizedLoss = 0.0;

   for (int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if (HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
      {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if (profit < 0) realizedLoss += profit;
      }
   }

   // Vérifier si la perte maximale est atteinte
   if (MathAbs(realizedLoss) >= maxLossAmount)
   {
      Print("Perte maximale de ", maxLossAmount, " atteinte. Trading arrêté.");
      return true;  // Arrêter la prise de nouvelles positions
   }

   return false;  // Continuer à trader
}

//+------------------------------------------------------------------+
//|                             Suivi_Tendance_Multi_Indicateurs.mq5 |
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

   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Code de désinitialisation si nécessaire
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Vérifier si la perte maximale est atteinte
   if(CheckMaxLossReached())
   {
      Print("Perte maximale atteinte. Aucun nouveau trade ne sera pris.");
      return; // Arrêter l'exécution si la perte maximale est atteinte
   }

   // Paramètres de la stratégie
   double riskPerTrade = 0.01;       // Risque en pourcentage par trade (1% du capital)
   int emaPeriod = 50;               // Période de l'EMA
   int rsiPeriod = 14;               // Période du RSI
   double rsiOverbought = 70;        // Seuil de surachat RSI
   double rsiOversold = 30;          // Seuil de survente RSI
   int atrPeriod = 14;               // Période de l'ATR (pour calculer SL et TP dynamiques)

   // Récupérer les informations du marché
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Calcul des indicateurs techniques
   double emaValue = iMA(_Symbol, _Period, emaPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double rsiValue = iRSI(_Symbol, _Period, rsiPeriod, PRICE_CLOSE, 0);
   double macdMain = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, 0);
   double macdSignal = iMACD(_Symbol, _Period, 12, 26, 9, PRICE_CLOSE, MODE_SIGNAL, 0);
   double atrValue = iATR(_Symbol, _Period, atrPeriod, 0); // Calculer l'ATR

   // Gestion des positions ouvertes
   int totalPositions = PositionsTotal();
   bool isPositionOpen = false;
   
   for(int i = 0; i < totalPositions; i++)
   {
      if(PositionSelect(_Symbol))
      {
         isPositionOpen = true;
         break;
      }
   }

   // Conditions d'entrée dans le marché (achat si prix > EMA, RSI < 70, et MACD > Signal)
   if(!isPositionOpen)
   {
      // Calcul du lot en fonction du risque
      double lot = CalculateLotSize(riskPerTrade, atrValue * 2);  // ATR utilisé pour ajuster la taille du SL
      double stopLossPips = atrValue * 2;  // Utilisation de 2 fois l'ATR pour le Stop Loss
      double takeProfitPips = atrValue * 4;  // Take Profit basé sur 4 fois l'ATR

      if(bid > emaValue && rsiValue < rsiOverbought && macdMain > macdSignal) // Achat
      {
         double stopLoss = bid - stopLossPips * point;
         double takeProfit = bid + takeProfitPips * point;
         OrderSend(_Symbol, OP_BUY, lot, ask, 2, stopLoss, takeProfit, "Achat Suivi de Tendance", 0, 0, clrGreen);
      }
      else if(bid < emaValue && rsiValue > rsiOversold && macdMain < macdSignal) // Vente
      {
         double stopLoss = ask + stopLossPips * point;
         double takeProfit = ask - takeProfitPips * point;
         OrderSend(_Symbol, OP_SELL, lot, bid, 2, stopLoss, takeProfit, "Vente Suivi de Tendance", 0, 0, clrRed);
      }
   }
  }
//+------------------------------------------------------------------+
//| Calcul de la taille du lot en fonction du risque                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPerTrade, double stopLossPips)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double lotStep = MarketInfo(_Symbol, MODE_MINLOT);
   double riskAmount = accountBalance * riskPerTrade; // Risque en fonction du solde du compte

   double pipValue = MarketInfo(_Symbol, MODE_TICKVALUE);
   double lotSize = riskAmount / (stopLossPips * pipValue);

   lotSize = MathMax(lotStep, NormalizeDouble(lotSize, 2)); // Ajuster la taille du lot au minimum permis
   return lotSize;
}

//+------------------------------------------------------------------+
//| Fonction pour vérifier si la perte maximale est atteinte          |
//+------------------------------------------------------------------+
bool CheckMaxLossReached()
{
   // Calculer le total des pertes réalisées
   double realizedLoss = 0.0;

   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
      {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if(profit < 0) realizedLoss += profit;
      }
   }

   // Vérifier si la perte maximale est atteinte
   if(MathAbs(realizedLoss) >= maxLossAmount)
   {
      Print("Perte maximale de ", maxLossAmount, " atteinte. Trading arrêté.");
      return true;  // Arrêter la prise de nouvelles positions
   }

   return false;  // Continuer à trader
}

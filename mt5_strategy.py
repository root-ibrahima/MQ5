import MetaTrader5 as mt5
import pandas as pd
import numpy as np

# Variables globales pour la gestion des risques
initial_balance = 0.0  # Solde initial au démarrage de l'EA
max_loss_percentage = 0.05  # Perte maximale autorisée (5% du solde initial)
max_loss_amount = 0.0  # Montant maximal de la perte autorisée
total_loss = 0.0  # Suivi des pertes réalisées

# Initialiser et se connecter à MT5
def initialize_mt5():
    if not mt5.initialize():
        print("Erreur lors de l'initialisation de MT5")
        return False
    account_info = mt5.account_info()
    if account_info is None:
        print("Erreur lors de la récupération des infos du compte")
        mt5.shutdown()
        return False
    global initial_balance, max_loss_amount
    initial_balance = account_info.balance
    max_loss_amount = initial_balance * max_loss_percentage
    print(f"EA démarré avec un solde initial de : {initial_balance}")
    print(f"Perte maximale autorisée : {max_loss_amount}")
    return True

# Fonction pour récupérer les données des indicateurs techniques
def get_indicators(symbol, timeframe):
    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, 100)
    df = pd.DataFrame(rates)
    
    # Calculer EMA
    df['ema'] = df['close'].ewm(span=50).mean()
    
    # Calculer RSI
    delta = df['close'].diff(1)
    gain = delta.clip(lower=0)
    loss = -1 * delta.clip(upper=0)
    avg_gain = gain.rolling(window=14).mean()
    avg_loss = loss.rolling(window=14).mean()
    rs = avg_gain / avg_loss
    df['rsi'] = 100 - (100 / (1 + rs))
    
    # Calculer MACD
    ema12 = df['close'].ewm(span=12).mean()
    ema26 = df['close'].ewm(span=26).mean()
    df['macd'] = ema12 - ema26
    df['macd_signal'] = df['macd'].ewm(span=9).mean()
    
    # Calculer ATR
    df['tr'] = np.maximum(df['high'] - df['low'], 
                          np.maximum(abs(df['high'] - df['close'].shift(1)), 
                                     abs(df['low'] - df['close'].shift(1))))
    df['atr'] = df['tr'].rolling(window=14).mean()

    return df.iloc[-1]  # Retourner les dernières valeurs

# Fonction pour vérifier si la perte maximale est atteinte
def check_max_loss_reached():
    # Obtenir l'historique des transactions réalisées
    history_deals = mt5.history_deals_get()
    realized_loss = sum([deal.profit for deal in history_deals if deal.profit < 0])
    
    if abs(realized_loss) >= max_loss_amount:
        print(f"Perte maximale de {max_loss_amount} atteinte. Trading arrêté.")
        return True
    return False

# Calculer la taille du lot en fonction du risque
def calculate_lot_size(risk_per_trade, stop_loss_pips, symbol):
    account_info = mt5.account_info()
    tick_size = mt5.symbol_info_tick(symbol).tick_size
    pip_value = tick_size  # Valeur d'un pip (dépend du symbole)
    risk_amount = account_info.balance * risk_per_trade  # Risque en fonction du solde du compte
    lot_size = risk_amount / (stop_loss_pips * pip_value)
    
    # Ajuster la taille du lot pour respecter les contraintes du broker
    min_volume = mt5.symbol_info(symbol).volume_min
    lot_size = max(min_volume, round(lot_size, 2))
    
    print(f"Taille de lot ajustée : {lot_size}")
    return lot_size

# Fonction pour envoyer les ordres de trading
def place_order(order_type, lot, symbol, price, stop_loss, take_profit):
    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": symbol,
        "volume": lot,
        "type": order_type,
        "price": price,
        "sl": stop_loss,
        "tp": take_profit,
        "deviation": 2,
        "magic": 123456,
        "comment": "Python EA Order"
    }
    
    result = mt5.order_send(request)
    if result.retcode != mt5.TRADE_RETCODE_DONE:
        print(f"Erreur lors de l'envoi de l'ordre : {result.retcode}")
        print(f"Détails de l'ordre - Volume: {lot}, Prix: {price}, SL: {stop_loss}, TP: {take_profit}")
        return False
    return True

# Fonction principale de la stratégie
def strategy(symbol, timeframe):
    if check_max_loss_reached():
        return

    indicators = get_indicators(symbol, timeframe)
    print(f"Indicateurs pour {symbol}: EMA={indicators['ema']}, RSI={indicators['rsi']}, MACD={indicators['macd']}, ATR={indicators['atr']}")

    ask = mt5.symbol_info_tick(symbol).ask
    bid = mt5.symbol_info_tick(symbol).bid
    
    # Conditions d'achat/vente
    if indicators['rsi'] < 70 and indicators['macd'] > indicators['macd_signal'] and bid > indicators['ema']:
        lot = calculate_lot_size(0.01, indicators['atr'] * 2, symbol)
        stop_loss = bid - indicators['atr'] * 2
        take_profit = bid + indicators['atr'] * 4
        place_order(mt5.ORDER_TYPE_BUY, lot, symbol, ask, stop_loss, take_profit)
    elif indicators['rsi'] > 30 and indicators['macd'] < indicators['macd_signal'] and bid < indicators['ema']:
        lot = calculate_lot_size(0.01, indicators['atr'] * 2, symbol)
        stop_loss = ask + indicators['atr'] * 2
        take_profit = ask - indicators['atr'] * 4
        place_order(mt5.ORDER_TYPE_SELL, lot, symbol, bid, stop_loss, take_profit)

# Lancer la stratégie
if initialize_mt5():
    strategy('EURUSD', mt5.TIMEFRAME_M1)
    mt5.shutdown()

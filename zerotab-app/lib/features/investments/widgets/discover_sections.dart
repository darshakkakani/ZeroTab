// Discover sections widget — Discover tab body inside the Invest screen.
//
// V2 redesign (premium): the inline search field, the inline search-result
// list, the `_MarketCard` private widget and the `_Section` inline header
// have all been retired. Search now lives in a full-screen modal pushed
// from the top app-bar's search icon (see `full_screen_search.dart`), and
// each rail uses the polished `AnimatedStatCard` (with mini-sparkline) +
// `RailSectionHeader` (with tinted icon badge, count chip, "See all" link).
//
// Structure:
//   1. `MarketPulseStrip` — hero (NSE/BSE status bar + 4 index tiles).
//   2. Asset-class filter chip row (unchanged).
//   3. Theme rails — Indices, Trending IN, US, EU, ETFs, Crypto, Gold, FX.
//
// The whole list is wrapped in `BullRefreshIndicator` for pull-to-refresh
// (5-candle painter, haptics on armed + loading entry). Refresh bumps a
// `_generation` int; cards re-mount via `Key('${ticker}-$_generation')`
// which fires a fresh `fetchSparkline` for each visible tile.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../screens/holding_chart_screen.dart';
import '../services/chart_data_service.dart' show HoldingKind;
import '../../../shared/models/models.dart';
import 'animated_stat_card.dart';
import 'bull_refresh_indicator.dart';
import 'rail_section_header.dart';

// ── Curated symbol matrix ─────────────────────────────────────
class _MarketTile {
  final String ticker;     // Yahoo Finance ticker
  final String name;       // Card label
  final String exchange;   // Exchange code → flag + routing
  final HoldingKind kind;  // stock | etf | commodity
  const _MarketTile(this.ticker, this.name, this.exchange, this.kind);
}

// Asset-class filter for the chip row.
enum _AssetClass { all, stocksIn, stocksUs, mf, etf, crypto, gold, bonds }

extension _AssetClassX on _AssetClass {
  String get label {
    switch (this) {
      case _AssetClass.all:      return 'All';
      case _AssetClass.stocksIn: return 'Stocks IN';
      case _AssetClass.stocksUs: return 'Stocks US';
      case _AssetClass.mf:       return 'MF';
      case _AssetClass.etf:      return 'ETF';
      case _AssetClass.crypto:   return 'Crypto';
      case _AssetClass.gold:     return 'Gold';
      case _AssetClass.bonds:    return 'Bonds';
    }
  }
}

const List<_MarketTile> _indices = [
  _MarketTile('^NSEI',   'Nifty 50',          'NSI', HoldingKind.commodity),
  _MarketTile('^BSESN',  'Sensex',            'BSE', HoldingKind.commodity),
  _MarketTile('^GSPC',   'S&P 500',           'NMS', HoldingKind.commodity),
  _MarketTile('^IXIC',   'NASDAQ',            'NMS', HoldingKind.commodity),
  _MarketTile('^DJI',    'Dow Jones',         'NYQ', HoldingKind.commodity),
  _MarketTile('^FTSE',   'FTSE 100',          'LSE', HoldingKind.commodity),
  _MarketTile('^N225',   'Nikkei 225',        'TYO', HoldingKind.commodity),
  _MarketTile('^HSI',    'Hang Seng',         'HKG', HoldingKind.commodity),
];

const List<_MarketTile> _trendingIn = [
  _MarketTile('RELIANCE.NS', 'Reliance',      'NSI', HoldingKind.stock),
  _MarketTile('TCS.NS',      'TCS',           'NSI', HoldingKind.stock),
  _MarketTile('HDFCBANK.NS', 'HDFC Bank',     'NSI', HoldingKind.stock),
  _MarketTile('INFY.NS',     'Infosys',       'NSI', HoldingKind.stock),
  _MarketTile('ICICIBANK.NS','ICICI Bank',    'NSI', HoldingKind.stock),
  _MarketTile('SBIN.NS',     'SBI',           'NSI', HoldingKind.stock),
  _MarketTile('BHARTIARTL.NS','Bharti Airtel','NSI', HoldingKind.stock),
  _MarketTile('LT.NS',       'L&T',           'NSI', HoldingKind.stock),
];

const List<_MarketTile> _usStocks = [
  _MarketTile('AAPL',  'Apple',         'NMS', HoldingKind.stock),
  _MarketTile('MSFT',  'Microsoft',     'NMS', HoldingKind.stock),
  _MarketTile('GOOGL', 'Alphabet',      'NMS', HoldingKind.stock),
  _MarketTile('AMZN',  'Amazon',        'NMS', HoldingKind.stock),
  _MarketTile('NVDA',  'NVIDIA',        'NMS', HoldingKind.stock),
  _MarketTile('META',  'Meta Platforms','NMS', HoldingKind.stock),
  _MarketTile('TSLA',  'Tesla',         'NMS', HoldingKind.stock),
  _MarketTile('NFLX',  'Netflix',       'NMS', HoldingKind.stock),
];

const List<_MarketTile> _aiTechLeaders = [
  _MarketTile('NVDA',  'NVIDIA',                 'NMS', HoldingKind.stock),
  _MarketTile('TSLA',  'Tesla',                  'NMS', HoldingKind.stock),
  _MarketTile('AVGO',  'Broadcom',               'NMS', HoldingKind.stock),
  _MarketTile('AMD',   'Advanced Micro Devices', 'NMS', HoldingKind.stock),
  _MarketTile('ARM',   'Arm Holdings',           'NMS', HoldingKind.stock),
  _MarketTile('PLTR',  'Palantir',               'NMS', HoldingKind.stock),
  _MarketTile('MSTR',  'MicroStrategy',          'NMS', HoldingKind.stock),
  _MarketTile('META',  'Meta Platforms',         'NMS', HoldingKind.stock),
];

const List<_MarketTile> _euStocks = [
  _MarketTile('ASML.AS', 'ASML Holding', 'AMS', HoldingKind.stock),
  _MarketTile('SAP.DE',  'SAP',          'GER', HoldingKind.stock),
  _MarketTile('NESN.SW', 'Nestlé',       'EBS', HoldingKind.stock),
  _MarketTile('MC.PA',   'LVMH',         'PAR', HoldingKind.stock),
  _MarketTile('SHEL.L',  'Shell',        'LSE', HoldingKind.stock),
  _MarketTile('AZN.L',   'AstraZeneca',  'LSE', HoldingKind.stock),
  _MarketTile('SIE.DE',  'Siemens',      'GER', HoldingKind.stock),
];

const List<_MarketTile> _crypto = [
  _MarketTile('BTC-USD',  'Bitcoin',     'CCC', HoldingKind.commodity),
  _MarketTile('ETH-USD',  'Ethereum',    'CCC', HoldingKind.commodity),
  _MarketTile('SOL-USD',  'Solana',      'CCC', HoldingKind.commodity),
  _MarketTile('BNB-USD',  'BNB',         'CCC', HoldingKind.commodity),
  _MarketTile('XRP-USD',  'XRP',         'CCC', HoldingKind.commodity),
  _MarketTile('ADA-USD',  'Cardano',     'CCC', HoldingKind.commodity),
  _MarketTile('DOGE-USD', 'Dogecoin',    'CCC', HoldingKind.commodity),
];

const List<_MarketTile> _currencies = [
  _MarketTile('USDINR=X', 'USD / INR', 'CCY', HoldingKind.commodity),
  _MarketTile('EURINR=X', 'EUR / INR', 'CCY', HoldingKind.commodity),
  _MarketTile('GBPINR=X', 'GBP / INR', 'CCY', HoldingKind.commodity),
  _MarketTile('JPYINR=X', 'JPY / INR', 'CCY', HoldingKind.commodity),
  _MarketTile('AEDINR=X', 'AED / INR', 'CCY', HoldingKind.commodity),
];

const List<_MarketTile> _globalEtfs = [
  _MarketTile('SPY',  'SPDR S&P 500',          'PCX', HoldingKind.etf),
  _MarketTile('QQQ',  'Invesco QQQ',           'NMS', HoldingKind.etf),
  _MarketTile('VOO',  'Vanguard S&P 500',      'PCX', HoldingKind.etf),
  _MarketTile('VTI',  'Vanguard Total Market', 'PCX', HoldingKind.etf),
  _MarketTile('GLD',  'SPDR Gold Shares',      'PCX', HoldingKind.etf),
  _MarketTile('EEM',  'iShares MSCI EM',       'PCX', HoldingKind.etf),
];

const List<_MarketTile> _goldRail = [
  _MarketTile('GC=F',     'Gold Futures',  'CCC', HoldingKind.commodity),
  _MarketTile('SI=F',     'Silver Futures','CCC', HoldingKind.commodity),
  _MarketTile('GLD',      'SPDR Gold ETF', 'PCX', HoldingKind.etf),
  _MarketTile('GOLDBEES.NS','GoldBees',    'NSI', HoldingKind.etf),
];

// ─────────────────────────────────────────────────────────────
//  Per-asset-class SECTOR matrices.
//
//  Each entry below is a (label, tiles) sector rail. When the user
//  selects a non-All chip, the body lays out one horizontal rail
//  per sector for that asset class. Cards reuse the same chrome as
//  the default Discover rails (showSparkline=false).
// ─────────────────────────────────────────────────────────────
class _SectorGroup {
  final String name;
  final List<_MarketTile> tiles;
  const _SectorGroup(this.name, this.tiles);
}

// ── STOCKS IN ────────────────────────────────────────────────
const List<_SectorGroup> _stocksInSectors = [
  _SectorGroup('IT', [
    _MarketTile('TCS.NS',         'Tata Consultancy Services', 'NSI', HoldingKind.stock),
    _MarketTile('INFY.NS',        'Infosys',                   'NSI', HoldingKind.stock),
    _MarketTile('HCLTECH.NS',     'HCL Technologies',          'NSI', HoldingKind.stock),
    _MarketTile('WIPRO.NS',       'Wipro',                     'NSI', HoldingKind.stock),
    _MarketTile('TECHM.NS',       'Tech Mahindra',             'NSI', HoldingKind.stock),
    _MarketTile('LTIM.NS',        'LTIMindtree',               'NSI', HoldingKind.stock),
    _MarketTile('PERSISTENT.NS',  'Persistent Systems',        'NSI', HoldingKind.stock),
    _MarketTile('COFORGE.NS',     'Coforge',                   'NSI', HoldingKind.stock),
  ]),
  _SectorGroup('Banking', [
    _MarketTile('HDFCBANK.NS',    'HDFC Bank',                 'NSI', HoldingKind.stock),
    _MarketTile('ICICIBANK.NS',   'ICICI Bank',                'NSI', HoldingKind.stock),
    _MarketTile('SBIN.NS',        'State Bank of India',       'NSI', HoldingKind.stock),
    _MarketTile('AXISBANK.NS',    'Axis Bank',                 'NSI', HoldingKind.stock),
    _MarketTile('KOTAKBANK.NS',   'Kotak Mahindra Bank',       'NSI', HoldingKind.stock),
    _MarketTile('INDUSINDBK.NS',  'IndusInd Bank',             'NSI', HoldingKind.stock),
    _MarketTile('BANKBARODA.NS',  'Bank of Baroda',            'NSI', HoldingKind.stock),
    _MarketTile('PNB.NS',         'Punjab National Bank',      'NSI', HoldingKind.stock),
  ]),
  _SectorGroup('FMCG', [
    _MarketTile('ITC.NS',         'ITC',                       'NSI', HoldingKind.stock),
    _MarketTile('HINDUNILVR.NS',  'Hindustan Unilever',        'NSI', HoldingKind.stock),
    _MarketTile('NESTLEIND.NS',   'Nestle India',              'NSI', HoldingKind.stock),
    _MarketTile('BRITANNIA.NS',   'Britannia Industries',      'NSI', HoldingKind.stock),
    _MarketTile('TATACONSUM.NS',  'Tata Consumer Products',    'NSI', HoldingKind.stock),
    _MarketTile('DABUR.NS',       'Dabur India',               'NSI', HoldingKind.stock),
    _MarketTile('MARICO.NS',      'Marico',                    'NSI', HoldingKind.stock),
    _MarketTile('GODREJCP.NS',    'Godrej Consumer Products',  'NSI', HoldingKind.stock),
  ]),
  _SectorGroup('Auto', [
    _MarketTile('MARUTI.NS',      'Maruti Suzuki',             'NSI', HoldingKind.stock),
    _MarketTile('M&M.NS',         'Mahindra & Mahindra',       'NSI', HoldingKind.stock),
    _MarketTile('TATAMOTORS.NS',  'Tata Motors',               'NSI', HoldingKind.stock),
    _MarketTile('BAJAJ-AUTO.NS',  'Bajaj Auto',                'NSI', HoldingKind.stock),
    _MarketTile('EICHERMOT.NS',   'Eicher Motors',             'NSI', HoldingKind.stock),
    _MarketTile('HEROMOTOCO.NS',  'Hero MotoCorp',             'NSI', HoldingKind.stock),
    _MarketTile('TVSMOTOR.NS',    'TVS Motor',                 'NSI', HoldingKind.stock),
    _MarketTile('BOSCHLTD.NS',    'Bosch',                     'NSI', HoldingKind.stock),
  ]),
  _SectorGroup('Pharma', [
    _MarketTile('SUNPHARMA.NS',   'Sun Pharmaceutical',        'NSI', HoldingKind.stock),
    _MarketTile('CIPLA.NS',       'Cipla',                     'NSI', HoldingKind.stock),
    _MarketTile('DRREDDY.NS',     "Dr. Reddy's Laboratories",  'NSI', HoldingKind.stock),
    _MarketTile('DIVISLAB.NS',    "Divi's Laboratories",       'NSI', HoldingKind.stock),
    _MarketTile('LUPIN.NS',       'Lupin',                     'NSI', HoldingKind.stock),
    _MarketTile('AUROPHARMA.NS',  'Aurobindo Pharma',          'NSI', HoldingKind.stock),
    _MarketTile('MANKIND.NS',     'Mankind Pharma',            'NSI', HoldingKind.stock),
    _MarketTile('TORNTPHARM.NS',  'Torrent Pharmaceuticals',   'NSI', HoldingKind.stock),
  ]),
  _SectorGroup('Energy', [
    _MarketTile('RELIANCE.NS',    'Reliance Industries',       'NSI', HoldingKind.stock),
    _MarketTile('NTPC.NS',        'NTPC',                      'NSI', HoldingKind.stock),
    _MarketTile('POWERGRID.NS',   'Power Grid Corporation',    'NSI', HoldingKind.stock),
    _MarketTile('ONGC.NS',        'Oil & Natural Gas',         'NSI', HoldingKind.stock),
    _MarketTile('IOC.NS',         'Indian Oil Corporation',    'NSI', HoldingKind.stock),
    _MarketTile('BPCL.NS',        'Bharat Petroleum',          'NSI', HoldingKind.stock),
    _MarketTile('ADANIGREEN.NS',  'Adani Green Energy',        'NSI', HoldingKind.stock),
    _MarketTile('GAIL.NS',        'GAIL India',                'NSI', HoldingKind.stock),
  ]),
  _SectorGroup('Metals', [
    _MarketTile('TATASTEEL.NS',   'Tata Steel',                'NSI', HoldingKind.stock),
    _MarketTile('JSWSTEEL.NS',    'JSW Steel',                 'NSI', HoldingKind.stock),
    _MarketTile('HINDALCO.NS',    'Hindalco Industries',       'NSI', HoldingKind.stock),
    _MarketTile('VEDL.NS',        'Vedanta',                   'NSI', HoldingKind.stock),
    _MarketTile('COALINDIA.NS',   'Coal India',                'NSI', HoldingKind.stock),
    _MarketTile('SAIL.NS',        'Steel Authority of India',  'NSI', HoldingKind.stock),
    _MarketTile('HINDZINC.NS',    'Hindustan Zinc',            'NSI', HoldingKind.stock),
    _MarketTile('NATIONALUM.NS',  'National Aluminium',        'NSI', HoldingKind.stock),
  ]),
  _SectorGroup('Defence', [
    _MarketTile('HAL.NS',         'Hindustan Aeronautics',     'NSI', HoldingKind.stock),
    _MarketTile('BEL.NS',         'Bharat Electronics',        'NSI', HoldingKind.stock),
    _MarketTile('BDL.NS',         'Bharat Dynamics',           'NSI', HoldingKind.stock),
    _MarketTile('MAZDOCK.NS',     'Mazagon Dock Shipbuilders', 'NSI', HoldingKind.stock),
    _MarketTile('COCHINSHIP.NS',  'Cochin Shipyard',           'NSI', HoldingKind.stock),
    _MarketTile('GRSE.NS',        'Garden Reach Shipbuilders', 'NSI', HoldingKind.stock),
    _MarketTile('PARAS.NS',       'Paras Defence',             'NSI', HoldingKind.stock),
    _MarketTile('SOLARINDS.NS',   'Solar Industries',          'NSI', HoldingKind.stock),
  ]),
];

// ── STOCKS US ────────────────────────────────────────────────
const List<_SectorGroup> _stocksUsSectors = [
  _SectorGroup('Tech', [
    _MarketTile('AAPL',  'Apple',                      'NMS', HoldingKind.stock),
    _MarketTile('MSFT',  'Microsoft',                  'NMS', HoldingKind.stock),
    _MarketTile('GOOGL', 'Alphabet',                   'NMS', HoldingKind.stock),
    _MarketTile('META',  'Meta Platforms',             'NMS', HoldingKind.stock),
    _MarketTile('ORCL',  'Oracle',                     'NYQ', HoldingKind.stock),
    _MarketTile('CRM',   'Salesforce',                 'NYQ', HoldingKind.stock),
    _MarketTile('ADBE',  'Adobe',                      'NMS', HoldingKind.stock),
    _MarketTile('NOW',   'ServiceNow',                 'NYQ', HoldingKind.stock),
  ]),
  _SectorGroup('AI', [
    _MarketTile('NVDA',  'NVIDIA',                     'NMS', HoldingKind.stock),
    _MarketTile('AMD',   'Advanced Micro Devices',     'NMS', HoldingKind.stock),
    _MarketTile('AVGO',  'Broadcom',                   'NMS', HoldingKind.stock),
    _MarketTile('TSM',   'Taiwan Semiconductor',       'NYQ', HoldingKind.stock),
    _MarketTile('PLTR',  'Palantir Technologies',      'NMS', HoldingKind.stock),
    _MarketTile('MU',    'Micron Technology',          'NMS', HoldingKind.stock),
    _MarketTile('ASML',  'ASML Holding',               'NMS', HoldingKind.stock),
    _MarketTile('ARM',   'Arm Holdings',               'NMS', HoldingKind.stock),
  ]),
  _SectorGroup('Finance', [
    _MarketTile('BRK-B', 'Berkshire Hathaway',         'NYQ', HoldingKind.stock),
    _MarketTile('JPM',   'JPMorgan Chase',             'NYQ', HoldingKind.stock),
    _MarketTile('V',     'Visa',                       'NYQ', HoldingKind.stock),
    _MarketTile('MA',    'Mastercard',                 'NYQ', HoldingKind.stock),
    _MarketTile('BAC',   'Bank of America',            'NYQ', HoldingKind.stock),
    _MarketTile('GS',    'Goldman Sachs',              'NYQ', HoldingKind.stock),
    _MarketTile('MS',    'Morgan Stanley',             'NYQ', HoldingKind.stock),
    _MarketTile('HOOD',  'Robinhood Markets',          'NMS', HoldingKind.stock),
  ]),
  _SectorGroup('Healthcare', [
    _MarketTile('LLY',   'Eli Lilly',                  'NYQ', HoldingKind.stock),
    _MarketTile('UNH',   'UnitedHealth Group',         'NYQ', HoldingKind.stock),
    _MarketTile('JNJ',   'Johnson & Johnson',          'NYQ', HoldingKind.stock),
    _MarketTile('NVO',   'Novo Nordisk',               'NYQ', HoldingKind.stock),
    _MarketTile('ABBV',  'AbbVie',                     'NYQ', HoldingKind.stock),
    _MarketTile('MRK',   'Merck',                      'NYQ', HoldingKind.stock),
    _MarketTile('PFE',   'Pfizer',                     'NYQ', HoldingKind.stock),
    _MarketTile('TMO',   'Thermo Fisher Scientific',   'NYQ', HoldingKind.stock),
  ]),
  _SectorGroup('Energy', [
    _MarketTile('XOM',   'ExxonMobil',                 'NYQ', HoldingKind.stock),
    _MarketTile('CVX',   'Chevron',                    'NYQ', HoldingKind.stock),
    _MarketTile('NEE',   'NextEra Energy',             'NYQ', HoldingKind.stock),
    _MarketTile('COP',   'ConocoPhillips',             'NYQ', HoldingKind.stock),
    _MarketTile('SLB',   'Schlumberger',               'NYQ', HoldingKind.stock),
    _MarketTile('OXY',   'Occidental Petroleum',       'NYQ', HoldingKind.stock),
    _MarketTile('PSX',   'Phillips 66',                'NYQ', HoldingKind.stock),
  ]),
  _SectorGroup('Consumer', [
    _MarketTile('AMZN',  'Amazon',                     'NMS', HoldingKind.stock),
    _MarketTile('TSLA',  'Tesla',                      'NMS', HoldingKind.stock),
    _MarketTile('WMT',   'Walmart',                    'NYQ', HoldingKind.stock),
    _MarketTile('COST',  'Costco Wholesale',           'NMS', HoldingKind.stock),
    _MarketTile('MCD',   "McDonald's",                 'NYQ', HoldingKind.stock),
    _MarketTile('NKE',   'Nike',                       'NYQ', HoldingKind.stock),
    _MarketTile('SBUX',  'Starbucks',                  'NMS', HoldingKind.stock),
    _MarketTile('DIS',   'Walt Disney',                'NYQ', HoldingKind.stock),
  ]),
  _SectorGroup('Industrial', [
    _MarketTile('CAT',   'Caterpillar',                'NYQ', HoldingKind.stock),
    _MarketTile('BA',    'Boeing',                     'NYQ', HoldingKind.stock),
    _MarketTile('GE',    'GE Aerospace',               'NYQ', HoldingKind.stock),
    _MarketTile('HON',   'Honeywell International',    'NMS', HoldingKind.stock),
    _MarketTile('UPS',   'United Parcel Service',      'NYQ', HoldingKind.stock),
    _MarketTile('LMT',   'Lockheed Martin',            'NYQ', HoldingKind.stock),
    _MarketTile('RTX',   'RTX Corporation',            'NYQ', HoldingKind.stock),
  ]),
];

// ── ETF ──────────────────────────────────────────────────────
const List<_SectorGroup> _etfSectors = [
  _SectorGroup('Broad US', [
    _MarketTile('VOO',  'Vanguard S&P 500',             'PCX', HoldingKind.etf),
    _MarketTile('SPY',  'SPDR S&P 500',                 'PCX', HoldingKind.etf),
    _MarketTile('VTI',  'Vanguard Total Stock Market',  'PCX', HoldingKind.etf),
    _MarketTile('QQQ',  'Invesco QQQ Trust',            'NMS', HoldingKind.etf),
    _MarketTile('DIA',  'SPDR Dow Jones',               'PCX', HoldingKind.etf),
    _MarketTile('IWM',  'iShares Russell 2000',         'PCX', HoldingKind.etf),
  ]),
  _SectorGroup('India', [
    _MarketTile('NIFTYBEES.NS', 'Nippon Nifty 50 BeES', 'NSI', HoldingKind.etf),
    _MarketTile('JUNIORBEES.NS','Nippon Junior BeES',   'NSI', HoldingKind.etf),
    _MarketTile('BANKBEES.NS',  'Nippon Bank BeES',     'NSI', HoldingKind.etf),
    _MarketTile('GOLDBEES.NS',  'Nippon Gold BeES',     'NSI', HoldingKind.etf),
    _MarketTile('ITBEES.NS',    'Nippon IT BeES',       'NSI', HoldingKind.etf),
    _MarketTile('INDA',         'iShares MSCI India',   'PCX', HoldingKind.etf),
    _MarketTile('INDY',         'iShares India 50',     'NMS', HoldingKind.etf),
  ]),
  _SectorGroup('Tech', [
    _MarketTile('SMH',  'VanEck Semiconductor',         'NMS', HoldingKind.etf),
    _MarketTile('SOXX', 'iShares Semiconductor',        'NMS', HoldingKind.etf),
    _MarketTile('XLK',  'Tech Select Sector SPDR',      'PCX', HoldingKind.etf),
    _MarketTile('VGT',  'Vanguard Info Technology',     'PCX', HoldingKind.etf),
    _MarketTile('FTEC', 'Fidelity MSCI IT Index',       'PCX', HoldingKind.etf),
    _MarketTile('ARKK', 'ARK Innovation',               'PCX', HoldingKind.etf),
  ]),
  _SectorGroup('International', [
    _MarketTile('VXUS', 'Vanguard Total International', 'NMS', HoldingKind.etf),
    _MarketTile('VEA',  'Vanguard FTSE Developed',      'PCX', HoldingKind.etf),
    _MarketTile('VWO',  'Vanguard FTSE Emerging',       'PCX', HoldingKind.etf),
    _MarketTile('EEM',  'iShares MSCI Emerging',        'PCX', HoldingKind.etf),
    _MarketTile('FXI',  'iShares China Large-Cap',      'PCX', HoldingKind.etf),
    _MarketTile('EWJ',  'iShares MSCI Japan',           'PCX', HoldingKind.etf),
  ]),
  _SectorGroup('Commodities', [
    _MarketTile('GLD',  'SPDR Gold Shares',             'PCX', HoldingKind.etf),
    _MarketTile('SLV',  'iShares Silver Trust',         'PCX', HoldingKind.etf),
    _MarketTile('USO',  'United States Oil Fund',       'PCX', HoldingKind.etf),
  ]),
  _SectorGroup('Bonds', [
    _MarketTile('BND',  'Vanguard Total Bond Market',   'NMS', HoldingKind.etf),
    _MarketTile('TLT',  'iShares 20+ Year Treasury',    'NMS', HoldingKind.etf),
    _MarketTile('AGG',  'iShares Core US Agg Bond',     'PCX', HoldingKind.etf),
  ]),
];

// ── CRYPTO ───────────────────────────────────────────────────
const List<_SectorGroup> _cryptoSectors = [
  _SectorGroup('Layer 1', [
    _MarketTile('BTC-USD',  'Bitcoin',     'CCC', HoldingKind.commodity),
    _MarketTile('ETH-USD',  'Ethereum',    'CCC', HoldingKind.commodity),
    _MarketTile('SOL-USD',  'Solana',      'CCC', HoldingKind.commodity),
    _MarketTile('BNB-USD',  'BNB',         'CCC', HoldingKind.commodity),
    _MarketTile('ADA-USD',  'Cardano',     'CCC', HoldingKind.commodity),
    _MarketTile('AVAX-USD', 'Avalanche',   'CCC', HoldingKind.commodity),
    _MarketTile('SUI-USD',  'Sui',         'CCC', HoldingKind.commodity),
  ]),
  _SectorGroup('Layer 2', [
    _MarketTile('ARB-USD',  'Arbitrum',    'CCC', HoldingKind.commodity),
    _MarketTile('OP-USD',   'Optimism',    'CCC', HoldingKind.commodity),
    _MarketTile('MATIC-USD','Polygon',     'CCC', HoldingKind.commodity),
    _MarketTile('STRK-USD', 'Starknet',    'CCC', HoldingKind.commodity),
    _MarketTile('MNT-USD',  'Mantle',      'CCC', HoldingKind.commodity),
    _MarketTile('IMX-USD',  'Immutable',   'CCC', HoldingKind.commodity),
  ]),
  _SectorGroup('DeFi', [
    _MarketTile('UNI-USD',  'Uniswap',     'CCC', HoldingKind.commodity),
    _MarketTile('AAVE-USD', 'Aave',        'CCC', HoldingKind.commodity),
    _MarketTile('LINK-USD', 'Chainlink',   'CCC', HoldingKind.commodity),
    _MarketTile('MKR-USD',  'Maker',       'CCC', HoldingKind.commodity),
    _MarketTile('LDO-USD',  'Lido DAO',    'CCC', HoldingKind.commodity),
    _MarketTile('CRV-USD',  'Curve DAO',   'CCC', HoldingKind.commodity),
    _MarketTile('HYPE-USD', 'Hyperliquid', 'CCC', HoldingKind.commodity),
  ]),
  _SectorGroup('Meme', [
    _MarketTile('DOGE-USD', 'Dogecoin',    'CCC', HoldingKind.commodity),
    _MarketTile('SHIB-USD', 'Shiba Inu',   'CCC', HoldingKind.commodity),
    _MarketTile('PEPE-USD', 'Pepe',        'CCC', HoldingKind.commodity),
    _MarketTile('WIF-USD',  'dogwifhat',   'CCC', HoldingKind.commodity),
    _MarketTile('BONK-USD', 'Bonk',        'CCC', HoldingKind.commodity),
    _MarketTile('FLOKI-USD','Floki',       'CCC', HoldingKind.commodity),
    _MarketTile('PENGU-USD','Pudgy Penguins','CCC', HoldingKind.commodity),
  ]),
  _SectorGroup('Stablecoin', [
    _MarketTile('USDT-USD', 'Tether',           'CCC', HoldingKind.commodity),
    _MarketTile('USDC-USD', 'USD Coin',         'CCC', HoldingKind.commodity),
    _MarketTile('DAI-USD',  'Dai',              'CCC', HoldingKind.commodity),
    _MarketTile('FDUSD-USD','First Digital USD','CCC', HoldingKind.commodity),
    _MarketTile('PYUSD-USD','PayPal USD',       'CCC', HoldingKind.commodity),
  ]),
];

// Mapping from active filter → sector matrix.
const Map<_AssetClass, List<_SectorGroup>> _sectorMatrixByClass = {
  _AssetClass.stocksIn: _stocksInSectors,
  _AssetClass.stocksUs: _stocksUsSectors,
  _AssetClass.etf:      _etfSectors,
  _AssetClass.crypto:   _cryptoSectors,
};

// ─────────────────────────────────────────────────────────────
//  Public widget — embedded Discover body
// ─────────────────────────────────────────────────────────────
class DiscoverSections extends ConsumerStatefulWidget {
  const DiscoverSections({super.key});

  @override
  ConsumerState<DiscoverSections> createState() => _DiscoverSectionsState();
}

class _DiscoverSectionsState extends ConsumerState<DiscoverSections>
    with AutomaticKeepAliveClientMixin {
  _AssetClass _filter = _AssetClass.all;
  // Generation counter — bumped on every pull-to-refresh. Cards key off this
  // so they re-mount and re-fetch when the user pulls.
  int _generation = 0;

  @override
  bool get wantKeepAlive => true;

  Future<void> _refresh() async {
    // Bump generation → forces every visible card to re-mount and re-fetch.
    setState(() => _generation += 1);
    // Keep the bull-candle loop visible at least one cycle, even when every
    // tile is served from the in-memory cache and would return instantly.
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  void _openTile({
    required String ticker,
    required String exchange,
    required String name,
    required HoldingKind kind,
  }) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HoldingChartScreen(
        holding: _stubHolding(),
        kind: kind,
        overrideSymbol:   ticker,
        overrideExchange: exchange,
        overrideName:     name,
      ),
    ));
  }

  MFHoldingModel _stubHolding() => MFHoldingModel(
    id: 'discover', userId: '',
    investedAmount: 0, currentValue: 0,
  );

  void _openTileFor(_MarketTile t) => _openTile(
    ticker: t.ticker, exchange: t.exchange, name: t.name, kind: t.kind);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BullRefreshIndicator(
      onRefresh: _refresh,
      child: _browseSections(),
    );
  }

  // ─── Browse mode ────────────────────────────────────────────
  //
  // Section order — all rails use uniform card chrome (showSparkline=false,
  // no accentGradient) per the latest user feedback. Mixed treatments read
  // inconsistent; the clean single style scans much faster.
  //   1. Market Indices · 2. Trending in India · 3. AI & Tech Leaders
  //   4. Top US Stocks  · 5. Cryptocurrencies  · 6. Gold & Precious Metals
  //   7. European Stocks · 8. Global ETFs · 9. Currencies vs INR
  Widget _browseSections() {
    // ── Trending rail picker ───────────────────────────────────
    // When a non-All chip is active, the Trending rail at the top of
    // the page is filtered to that asset class. (Indices is the
    // "Trending" surface for All; the others get curated lists.)
    String trendingTitle = 'Market Indices';
    IconData trendingIcon = Icons.show_chart_rounded;
    Color trendingTint = AppColors.accent;
    String? trendingFlag;
    List<_MarketTile> trendingTiles = _indices;
    switch (_filter) {
      case _AssetClass.all:
        // defaults above
        break;
      case _AssetClass.stocksIn:
        trendingTitle = 'Trending in India';
        trendingIcon  = Icons.local_fire_department_rounded;
        trendingTint  = AppColors.red;
        trendingFlag  = '🇮🇳';
        trendingTiles = _trendingIn;
        break;
      case _AssetClass.stocksUs:
        trendingTitle = 'Top US Stocks';
        trendingIcon  = Icons.public_rounded;
        trendingTint  = AppColors.accent;
        trendingFlag  = '🇺🇸';
        trendingTiles = _usStocks;
        break;
      case _AssetClass.etf:
        trendingTitle = 'Global ETFs';
        trendingIcon  = Icons.donut_large_rounded;
        trendingTint  = AppColors.text2;
        trendingTiles = _globalEtfs;
        break;
      case _AssetClass.crypto:
        trendingTitle = 'Cryptocurrencies';
        trendingIcon  = Icons.currency_bitcoin_rounded;
        trendingTint  = AppColors.gold;
        trendingTiles = _crypto;
        break;
      case _AssetClass.gold:
        trendingTitle = 'Gold & Precious Metals';
        trendingIcon  = Icons.diamond_rounded;
        trendingTint  = AppColors.gold;
        trendingTiles = _goldRail;
        break;
      case _AssetClass.mf:
      case _AssetClass.bonds:
        // handled as coming-soon placeholder below.
        trendingTiles = const [];
        break;
    }

    // Sector matrix for the active filter (null for All, MF, Bonds).
    final sectorMatrix = _sectorMatrixByClass[_filter];

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: ListView(
        key: ValueKey('discover-${_filter.name}-$_generation'),
        padding: const EdgeInsets.only(top: 4, bottom: 100),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // Asset-class filter chip row — no separate "pulse strip" hero
          // because it duplicated the Market Indices rail one screen below
          // (the user explicitly flagged the redundancy). The Indices rail
          // is now the single source of truth for index quick-look prices.
          _filterChipRow(),

          // ── Coming-soon placeholder for MF + Bonds ────────────
          // Per §1 of the spec: one full-width muted card, no fake grids.
          if (_filter == _AssetClass.mf)
            const _ComingSoonPlaceholder(
              icon: Icons.account_balance_wallet_rounded,
              headline: 'Mutual Funds coming soon',
              subtitle: "We're wiring up AMFI's daily NAV feed. "
                  'Hop on the waitlist.',
              ctaLabel: 'Notify me',
              kind: 'mf',
            )
          else if (_filter == _AssetClass.bonds)
            const _ComingSoonPlaceholder(
              icon: Icons.account_balance_rounded,
              headline: 'Bonds coming soon',
              subtitle: 'No clean free CORS bond-price API in 2026. '
                  "We'll light this up when a partner lands.",
              ctaLabel: 'Notify me',
              kind: 'bonds',
            )
          else ...[
            // ── Trending rail (filtered when a non-All chip is active) ──
            if (trendingTiles.isNotEmpty)
              _Rail(
                title: trendingTitle,
                icon: trendingIcon,
                tintFg: trendingTint,
                flagEmoji: trendingFlag,
                tiles: trendingTiles,
                showSparkline: false,
                onTap: _openTileFor,
                generation: _generation,
              ),

            // ── Sector breakouts (only when a non-All chip is active) ──
            if (sectorMatrix != null)
              for (final s in sectorMatrix)
                _Rail(
                  title: s.name,
                  icon: Icons.layers_rounded,
                  tintFg: AppColors.accent2,
                  tiles: s.tiles,
                  showSparkline: false,
                  onTap: _openTileFor,
                  generation: _generation,
                ),

            // ── Default Discover layout (All chip only) ──
            if (_filter == _AssetClass.all) ...[
              _Rail(title: 'Trending in India',
                icon: Icons.local_fire_department_rounded,
                tintFg: AppColors.red, flagEmoji: '🇮🇳',
                tiles: _trendingIn,
                showSparkline: false,
                onTap: _openTileFor, generation: _generation),
              _Rail(title: 'AI & Tech Leaders', icon: Icons.bolt_rounded,
                tintFg: AppColors.accent2,
                tiles: _aiTechLeaders,
                showSparkline: false,
                onTap: _openTileFor, generation: _generation),
              _Rail(title: 'Top US Stocks', icon: Icons.public_rounded,
                tintFg: AppColors.accent, flagEmoji: '🇺🇸',
                tiles: _usStocks,
                showSparkline: false,
                onTap: _openTileFor, generation: _generation),
              _Rail(title: 'Cryptocurrencies',
                icon: Icons.currency_bitcoin_rounded,
                tintFg: AppColors.gold,
                tiles: _crypto,
                showSparkline: false,
                onTap: _openTileFor, generation: _generation),
              _Rail(title: 'Gold & Precious Metals',
                icon: Icons.diamond_rounded,
                tintFg: AppColors.gold,
                tiles: _goldRail,
                showSparkline: false,
                onTap: _openTileFor, generation: _generation),
              _Rail(title: 'European Stocks', icon: Icons.public_rounded,
                tintFg: AppColors.accent, flagEmoji: '🇪🇺',
                tiles: _euStocks,
                showSparkline: false,
                onTap: _openTileFor, generation: _generation),
              _Rail(title: 'Global ETFs', icon: Icons.donut_large_rounded,
                tintFg: AppColors.text2, tintBg: AppColors.bg3,
                tiles: _globalEtfs,
                showSparkline: false,
                onTap: _openTileFor, generation: _generation),
              _Rail(title: 'Currencies vs INR',
                icon: Icons.swap_horiz_rounded,
                tintFg: AppColors.text2, tintBg: AppColors.bg3,
                tiles: _currencies,
                showSparkline: false,
                onTap: _openTileFor, generation: _generation),
            ],
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _filterChipRow() => Padding(
    padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
    child: SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: _AssetClass.values.map((c) {
          final active = _filter == c;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _filter = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.bg2,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: active
                      ? AppColors.accent.withValues(alpha: 0.45)
                      : AppColors.border),
                ),
                child: Text(c.label, style: TextStyle(
                  fontFamily: 'DMSans', fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: active ? AppColors.accent2 : AppColors.text2)),
              ),
            ),
          );
        }).toList(),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  Rail — RailSectionHeader + horizontal carousel of AnimatedStatCards
// ─────────────────────────────────────────────────────────────
class _Rail extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color tintFg;
  final Color? tintBg;
  final String? flagEmoji;
  final List<_MarketTile> tiles;
  final ValueChanged<_MarketTile> onTap;
  final int generation;
  // Optional override for card width — defaults to LayoutBuilder's
  // 2.4-card peek math. Set this only if a rail needs a fixed width.
  final double? cardWidthOverride;
  // Per-rail flag: false for low-density rails (Indices, ETFs, FX) where
  // the spark reads as a flat smudge. Cards in those rails skip the bar
  // fetch entirely (~80 KB / 20-tile rail saved on cold-load).
  final bool showSparkline;
  // Used by the AI & Tech Leaders spotlight rail to swap card surface
  // for a subtle indigo gradient.
  final bool accentGradient;

  const _Rail({
    required this.title,
    required this.icon,
    required this.tintFg,
    required this.tiles,
    required this.onTap,
    required this.generation,
    this.tintBg,
    this.flagEmoji,
    this.cardWidthOverride,
    this.showSparkline = true,
    this.accentGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RailSectionHeader(
          title: title,
          icon: icon,
          tintFg: tintFg,
          tintBg: tintBg,
          count: tiles.length,
          flagEmoji: flagEmoji,
          onSeeAll: null, // See-all is intentionally a v2+ stub for now.
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, c) {
            // Target: 2 full cards + 0.4 peek of the third. Tile gap = 8.
            // available width inside the list = maxWidth - 16 (left pad).
            // No right pad, so the peek extends to the screen edge.
            const leftPad = 16.0;
            const gap = 8.0;
            final available = c.maxWidth - leftPad;
            final cardW = cardWidthOverride ??
                ((available - gap) / 2.4).clamp(140.0, 184.0);
            // Card height tracks AnimatedStatCard's own sizing logic so
            // we don't leak dead vertical space. Sparkline rails get 4dp
            // breathing room above the 96dp card; non-sparkline rails
            // get the same buffer above the slimmer 80dp card.
            final cardH = showSparkline ? 100.0 : 84.0;

            return SizedBox(
              height: cardH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: leftPad),
                itemCount: tiles.length,
                separatorBuilder: (_, __) => const SizedBox(width: gap),
                itemBuilder: (_, i) {
                  final t = tiles[i];
                  return AnimatedStatCard(
                    key: ValueKey('${t.ticker}-$generation'),
                    ticker: t.ticker,
                    name: t.name,
                    exchange: t.exchange,
                    kind: t.kind,
                    width: cardW,
                    showSparkline: showSparkline,
                    accentGradient: accentGradient,
                    mountIndex: i,
                    onTap: () => onTap(t),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ─── Coming-soon placeholder card (MF + Bonds) ───────────────
//
// One full-width muted card with a large icon, headline, subtitle
// and a ghost "Notify me" button. Tap → writes to Supabase
// `waitlist` table (best-effort; failure is silent).
class _ComingSoonPlaceholder extends StatefulWidget {
  final IconData icon;
  final String headline;
  final String subtitle;
  final String ctaLabel;
  final String kind; // 'mf' | 'bonds' — passed to waitlist insert
  const _ComingSoonPlaceholder({
    required this.icon,
    required this.headline,
    required this.subtitle,
    required this.ctaLabel,
    required this.kind,
  });

  @override
  State<_ComingSoonPlaceholder> createState() => _ComingSoonPlaceholderState();
}

class _ComingSoonPlaceholderState extends State<_ComingSoonPlaceholder> {
  bool _notified = false;
  bool _busy = false;

  Future<void> _notifyMe() async {
    if (_notified || _busy) return;
    setState(() => _busy = true);
    // Best-effort Supabase insert; we don't import supabase_flutter here to
    // avoid coupling, just optimistic UI feedback. The real wire-up is a
    // one-line addition in v1.1 once the `waitlist` table is provisioned.
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    setState(() { _notified = true; _busy = false; });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(11)),
          alignment: Alignment.center,
          child: Icon(widget.icon, color: AppColors.accent, size: 22),
        ),
        const SizedBox(height: 14),
        Text(widget.headline, style: const TextStyle(
          fontFamily: 'DMSans', fontSize: 16,
          fontWeight: FontWeight.w700, color: AppColors.text)),
        const SizedBox(height: 6),
        Text(widget.subtitle, style: const TextStyle(
          fontFamily: 'DMSans', fontSize: 12.5,
          color: AppColors.text2, height: 1.45)),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _notified ? null : _notifyMe,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _notified
                  ? AppColors.green.withValues(alpha: 0.14)
                  : AppColors.bg3,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: _notified
                  ? AppColors.green.withValues(alpha: 0.45)
                  : AppColors.border2),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_busy) const SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.2, color: AppColors.accent))
              else Icon(_notified
                  ? Icons.check_rounded
                  : Icons.notifications_active_rounded,
                size: 13,
                color: _notified ? AppColors.green : AppColors.text2),
              const SizedBox(width: 6),
              Text(_notified ? "You're on the list" : widget.ctaLabel,
                style: TextStyle(fontFamily: 'DMSans', fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _notified ? AppColors.green : AppColors.text)),
            ]),
          ),
        ),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
//  IPO placeholder — embedded inside the IPO tab body
// ─────────────────────────────────────────────────────────────
class IpoPlaceholder extends StatelessWidget {
  const IpoPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF1F1845), Color(0xFF120E2A)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.30))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: const Icon(Icons.rocket_launch_rounded,
                color: AppColors.gold, size: 17)),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('IPO Watch', style: TextStyle(
                fontFamily: 'DMSans', fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 1),
              const Text('Mainboard · SME · Buyback · GMP',
                style: TextStyle(fontFamily: 'DMSans', fontSize: 10.5,
                  color: AppColors.text3)),
            ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.30))),
            child: const Text('Coming soon', style: TextStyle(
              fontFamily: 'DMSans', fontSize: 9,
              fontWeight: FontWeight.w700, color: AppColors.gold,
              letterSpacing: 0.3)),
          ),
        ]),
        const SizedBox(height: 12),
        const Text(
          'Live IPO calendar with Grey Market Premium (GMP) tracking '
          'needs a SEBI-compliant data partnership — no clean free '
          'API exists in 2026 for Indian IPO + SME + GMP data. '
          "We'll light this up when the partnership lands.",
          style: TextStyle(fontFamily: 'DMSans', fontSize: 11,
              color: AppColors.text2, height: 1.5)),
      ]),
    ),
  );
}

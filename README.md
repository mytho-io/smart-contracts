# 📜 Project Structure  

## TotemFactory.sol  
💡 **Purpose:** Creates totems and stores totem data.  

### Functions:  
- `createTotem(metaData, name, symbol)` – Creates a new totem with a new `TotemToken`.  
- `createTotemWithExistingToken(uint256 tokenId)` – Creates a new totem with an existing ERC20/ERC721 token. Merit system for the created totem activates immediately.  
- `addTokenToWhitelist(address tokenAddr)` – Adds an existing token to the whitelist.  
- `removeTokenFromWhitelist(address tokenAddr)` – Removes a token from the whitelist.  

---

## Totem.sol *(Governance Contract)*  
💡 **Purpose:** Governance logic for each totem. Uses `ProxyBeacon` as part of OpenZeppelin's `UpgradeableBeacon` system. All Totem contracts share a common implementation.  

### Functions:  
- `meritBoost()` – Earn merit for the totem holder during the Mythum subperiod.  
- `collectMYTH()` – Collect accumulated `MYTH` from `MeritManager`.  

---

## TotemDistributor.sol *(Totem Token Sale & Distribution)*  
💡 **Purpose:** Handles `TotemToken` distribution, sales, and burning. Uses an oracle for `MYTH/USD` conversion.  

### Functions:  
- `buy(uint256 amount)` – Buy `TotemTokens` during the sale period.  
  - **Limits:**  
    - Maximum **5,000,000** tokens per address.  
    - **Price:** $0.00004 per `TotemToken`.  
- `sell(uint256 amount)` – Sell `TotemTokens` during the sale period.  

### Conditions:  
- When all tokens are sold:  
  - Merit system **activates**.  
  - `Buy/Sell` **becomes unavailable**.  
  - `burnTotems()` **becomes available**.  
  - `TotemToken` **becomes transferable**.  

### MYTH Distribution:  
- **2.5%** → `revenuePool`.  
- **0.5%** → Totem creator.  
- **Remaining** → Totem's treasury.  
- **Send liquidity to AMM.**  
- **Received LP sent to Totem’s treasury.**  

### Additional Functions:  
- `burnTotems()` – Burn `TotemTokens` and receive `MYTH` tokens in return.  
  - `MYTH` share is proportional to the user's `TotemToken` share in circulation.  
- `exchangeTotems()` – Exchange custom tokens for `MYTH` from the Totem’s treasury.  
  - Custom tokens are sent to the Totem’s treasury.  

---

## MeritManager.sol *(Merit System Controller)*  
💡 **Purpose:** Manages merit accumulation and distribution. Tracks Mytho periods.  

### Functions:  
- `boostTotem(address totemAddress, uint256 amount)` – Called once per period by a `Totem` contract to increase merit balance.  
- `collectMYTH()` – Claim accumulated `MYTH` for a `Totem` contract.  
- `creditMerit(address totemAddress, uint256 amount)` – Credit merit manually to a selected `Totem` based on off-chain actions.  
- `addToBlacklist(address totemAddress)` – Add totem to blacklist.  
- `removeFromBlacklist(address totemAddress)` – Remove totem from blacklist.  

---

## MYTHVesting.sol *(MYTH Distribution Vesting Contract)*  
💡 **Purpose:** Handles `MYTH` distribution via vesting.  

---

## TotemToken.sol *(ERC20 Token with OP Compatibility)*  
💡 **Purpose:** Custom ERC20 token, non-transferable until the end of the sale period.  

### Functions:  
- `constructor()` – Mints **1,000,000,000** tokens, distributed as follows:  
  - **250,000** → Totem creator.  
  - **100,000,000** → Totem treasury.  
  - **899,750,000** → `TotemDistributor`.  
- `transfer()` – Disabled during the sale period.  

---

## MYTH.sol *(ERC20 Token with OP Compatibility)*  
💡 **Purpose:** `MYTH` token, distributed via `MYTHVesting`.  

PROMT:

Я разрабатываю блокчейн протокол. Вот его структура:

MeritManager
- это контракт должен регистрировать тотем, когда заканчивается sale period. 
- Мерит будет начисляться менеджером через функцию creditMerit. 
- Вестинг будет постепенно начислять токены MYTHO на баланс контракта MeritManager. 
- Должна быть возможность добавить адрес тотема в блэклист и если тотем в нем, он не может получать мерит поинты. 
- Работа протокола будет поделена на периоды, каждый из которых равен 30 дней, они будут считаться в контракте MeritManager, текущий период возвращается в currentPeriod. 
- также последняя четверть периода называется mythus, это должно возвращаться в функции isMythus. 
- Каждый пользователь, у кого есть какое-то количество тотем токенов, может 1 раз в mythus период вызвать boostTotem и увеличить количество мерит на балансе тотема на переменную oneTotemBoost, которая может быть изменена менеджером. Если пользователь уже проголосовал за 1 тотем, то за другой тотем в текущем периоде он проголосовать уже не может. 
- Когда мерит распределяется любым способом во время периода Mythus, то он имеет мультипликатор 1.5, он тоже должен быть в виде переменной, которую можно поменять. 
- Также При вызове пользователями totemBoost должна взиматься плата в нативных токенах, размер которой также задается в переменной. 
- И в конце месяца MYTHO распределяется между сообществами, пропорционально накопленным очкам Merit. Для того чттобы склеймить накопленные MYTHO тотем может вызвать для этого отдельную фукнцию в MeritManager.

MYTHO
Назначение: Создание токена MYTHO Government Token с общей эмиссией 1 миллиард токенов и их распределением между различными категориями (инсентивы, команда, казна, AMM, airdrop).
Основные характеристики:
Общий запас: 1 миллиард токенов (18 decimals).
Распределение:
50% (500M) — инсентивы для Totem (4 года с ежегодным выпуском: 175M, 125M, 100M, 50M).
20% (200M) — команда (vesting 2 года).
18% (180M) — казна (без vesting).
7% (70M) — AMM-инсентивы (vesting 2 года).
5% (50M) — airdrop (без vesting).
Функционал:
Конструктор: Разворачивает токен, создает vesting-кошельки и распределяет токены.
burn: Позволяет владельцу сжигать свои токены.
mint (тестовая): Минтит токены (вероятно, для тестирования).
Ограничения:
Нулевые адреса для получателей запрещены.
Сжигание токенов доступно только владельцу.
Особенности:
Использует VestingWallet для постепенного выпуска токенов (1–4 года).
Не обновляемый контракт, что фиксирует логику распределения.
Контракт предназначен для управления токеном MYTHO с акцентом на долгосрочное распределение через vesting и немедленный доступ для казны и airdrop. Тестовая функция mint указывает на возможность доработки для разработчиков.

Totem
Назначение: Хранение и управление токенами TotemToken и MYTH, а также предоставление данных о резервах и хэше данных.
Основные характеристики:
Инициализируется с адресами токенов TotemToken и MYTH, а также хэшем данных (dataHash).
Поддерживает роли для управления доступом.
Предоставляет базовые функции для работы с резервами и накоплением MYTH.
Роли:
DEFAULT_ADMIN_ROLE: Администратор (назначен создателю контракта).
MANAGER: Менеджер (назначен создателю контракта).
Ключевые функции:
initialize: Устанавливает токены и хэш данных при создании.
meritBoost: Позволяет владельцам TotemToken получать MYTH в определенный период (реализация отсутствует).
collectMYTH: Сбор накопленных MYTH из MeritManager (реализация отсутствует).
getReserves: Возвращает баланс TotemToken и MYTH на контракте.
getDataHash: Возвращает хэш данных, связанный с Totem.
Ограничения:
Функции meritBoost и collectMYTH пока не реализованы.
Логика взаимодействия с новыми токенами ограничена до полной продажи токенов (указание в комментарии).
Контракт служит основой для управления резервами и интеграции с системой заслуг, но требует доработки для полной функциональности (например, реализации meritBoost и collectMYTH). Предназначен для хранения активов и предоставления информации о состоянии Totem.

TotemFactory
Назначение: Создание новых экземпляров Totem и их токенов (TotemToken), а также регистрация Totem с уже существующими токенами.
Основные характеристики:
Создает Totem с новым токеном (createTotem) или использует существующий токен (createTotemWithExistingToken).
Использует BeaconProxy для развертывания Totem с заданными параметрами (адрес токена, mythAddr, хэш данных).
Хранит информацию о каждом Totem (создатель, адрес токена, адрес Totem, хэш данных, флаг кастомного токена).
Роли:
DEFAULT_ADMIN_ROLE: Администратор (назначен создателю контракта).
MANAGER: Менеджер, управляющий белым списком токенов.
WHITELISTED: Роль для токенов, разрешенных для использования в createTotemWithExistingToken.
Процесс:
createTotem: Разворачивает новый TotemToken, создает прокси для Totem и регистрирует его в TotemTokenDistributor.
createTotemWithExistingToken: Создает Totem с уже существующим токеном из белого списка (без создания нового токена).
Оба метода требуют оплаты комиссии в ASTR (реализация не завершена).
Ключевые функции:
createTotem: Создание Totem с новым токеном (имя, символ, хэш данных).
createTotemWithExistingToken: Создание Totem с существующим токеном из белого списка.
addTokenToWhitelist / removeTokenFromWhitelist: Управление белым списком токенов (доступно менеджеру).
Ограничения:
Для использования существующих токенов они должны быть в белом списке.
Создание Totem связано с TotemTokenDistributor для дальнейшего распределения токенов.
Контракт предназначен для гибкого развертывания новых Totem с уникальными токенами или интеграции существующих токенов, с учетом контроля доступа и будущей интеграции с системой заслуг (merit system). Некоторые функции (например, оплата в ASTR) требуют доработки.

- TotemToken
Назначение: Создает токен с ограничениями на переводы во время "периода продаж" (sale period) и управлением ролями.
Основные характеристики:
Изначально выпускается 1 миллиард токенов, которые передаются дистрибьютору (totemDistributor).
Во время периода продаж (salePeriod = true) токены могут передаваться только от дистрибьютора и только на адреса из списка разрешенных получателей (allowedRecipients).
После завершения периода продаж (функция openTransfers) ограничения снимаются, и токены становятся свободно передаваемыми.
Роли:
DEFAULT_ADMIN_ROLE: Администратор (назначен создателю контракта).
MANAGER: Менеджер, который может добавлять/удалять адреса из списка разрешенных получателей.
totemDistributor: Дистрибьютор, который управляет токенами в период продаж и может открыть свободные трансферы.
Ограничения:
Трансферы во время периода продаж блокируются, если получатель не в списке allowedRecipients и отправитель не дистрибьютор.
Только дистрибьютор может завершить период продаж.
Функции:
addAllowedRecipient / removeAllowedRecipient: Управление списком разрешенных получателей (доступно менеджеру).
openTransfers: Завершение периода продаж (доступно дистрибьютору).
isAllowedRecipient: Проверка статуса адреса в списке разрешенных.
Контракт подходит для сценариев контролируемого распределения токенов, например, при первичной продаже (ICO), с последующим переходом к свободному обращению.

TotemTokenDistributor
Назначение: Управление продажей токенов Totem в периоде продаж (sale period) и их дальнейшим обращением, включая распределение доходов и добавление ликвидности.
Основные характеристики:
Пользователи могут покупать (buy) и продавать (sell) токены Totem за определенные платежные токены в периоде продаж.
После завершения периода продаж токены становятся свободно передаваемыми, а собранные платежные токены распределяются между пулом доходов, создателем, хранилищем и ликвидностью.
Ограничение на максимальное количество токенов на адрес (maxTokensPerAddress = 5M).
Цена одного Totem в USD фиксирована (oneTotemPriceInUsd = 0.00004 ether).
Роли:
DEFAULT_ADMIN_ROLE: Администратор (назначен создателю контракта).
MANAGER: Менеджер, управляющий настройками (например, адрес платежного токена, фабрика).
Процесс:
Регистрация Totem через TotemFactory: 250K токенов создателю, 100M токенов в контракт Totem.
Покупка: пользователь платит платежными токенами, получает Totem (с учетом лимитов).
Продажа: пользователь возвращает Totem, получает часть платежных токенов обратно.
Завершение периода продаж: токены распределяются (2.5% — пул доходов, 0.5% — создатель, 68.43% — хранилище, 28.57% — ликвидность в AMM).
Ключевые функции:
buy: Покупка токенов в периоде продаж.
sell: Продажа токенов в периоде продаж.
register: Регистрация нового Totem через фабрику.
_closeSalePeriod: Завершение периода продаж и распределение токенов.
Ограничения:
Покупка/продажа доступны только в периоде продаж.
Пользователь не может превысить лимит токенов на адрес.
Поддерживаются только стандартные токены (не кастомные).
Контракт предназначен для контролируемой продажи токенов с последующим переходом к децентрализованному обращению и интеграцией с AMM (автоматизированный маркет-мейкер) для ликвидности. Некоторые функции (например, работа с оракулами и нативными токенами) требуют доработки.

если будешь писать код, комментарии должны быть на английский языке в формате NatSpec
используй только кастомные ошибки
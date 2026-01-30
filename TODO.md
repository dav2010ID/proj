# TODO: Architecture Improvements

## P1: Core Refactoring

### 5. Разделить Core Planner и Runtime Scheduler

#### 5.1 Создать `core/plan_graph.lua`
- [ ] Определить структуру `PlanGraph`
  ```lua
  PlanGraph = {
    nodes = {},  -- { CraftNode, SupplyNode }
    edges = {}   -- dependencies between nodes
  }
  ```
- [ ] Реализовать типы узлов:
  - [ ] `CraftNode { recipe, count, deps }`
  - [ ] `SupplyNode { item, count, storage_id }`
- [ ] Добавить методы графа:
  - [ ] `add_node(node) -> node_id`
  - [ ] `add_edge(from_id, to_id)`
  - [ ] `get_dependencies(node_id) -> {node_id...}`
  - [ ] `topological_sort() -> {node_id...}`

#### 5.2 Рефакторить `core/planner.lua`
- [ ] Убрать из planner всю логику времени/ресурсов
- [ ] Изменить возвращаемое значение: вместо списка шагов → `PlanGraph`
- [ ] Оставить только:
  - [ ] DFS по рецептам
  - [ ] Построение дерева зависимостей
  - [ ] Расчёт количеств (без времени)
- [ ] Удалить упоминания `runtime`, `storage`, `time`

#### 5.3 Создать `runtime/scheduler.lua`
- [ ] Принимает `PlanGraph` от planner
- [ ] Добавляет информацию о времени:
  - [ ] Длительность крафта
  - [ ] Async delays
  - [ ] Параллелизм
- [ ] Реализовать методы:
  - [ ] `schedule(plan_graph, state) -> {ExecutionTask...}`
  - [ ] `get_ready_tasks(state) -> {task...}`
  - [ ] `update_after_completion(task, state)`

#### 5.4 Обновить `runtime/executor.lua`
- [ ] Принимать граф вместо списка
- [ ] Использовать `scheduler` для определения готовых задач
- [ ] Исполнять узлы графа по мере готовности зависимостей
- [ ] Отслеживать завершённые узлы

#### 5.5 Тесты
- [ ] `tests/core/plan_graph_spec.lua` - тесты структуры графа
- [ ] `tests/core/planner_spec.lua` - planner возвращает граф, без времени
- [ ] `tests/runtime/scheduler_spec.lua` - scheduler работает с графом
- [ ] Интеграционный тест: planner → scheduler → executor

---

## P2: Provider Capabilities

### 6. Capability System

#### 6.1 Создать `core/capability.lua`
- [ ] Определить базовые capability типы:
  ```lua
  Capabilities = {
    batch = { max_items, max_total },
    async = boolean,
    parallel = boolean,
    transactional = boolean
  }
  ```
- [ ] Добавить валидацию capability объектов
- [ ] Создать helper методы:
  - [ ] `has_capability(provider, cap_name) -> boolean`
  - [ ] `get_capability_limits(provider, cap_name) -> limits`

#### 6.2 Обновить Provider Contract
- [ ] Добавить в базовый интерфейс provider:
  ```lua
  provider.capabilities = {
    batch = nil,  -- or { max_items = N, max_total = M }
    async = false,
    parallel = false
  }
  ```
- [ ] Обновить все существующие providers:
  - [ ] `chest_adapter` - добавить capabilities
  - [ ] `virtual_storage` - добавить capabilities
  - [ ] `memory_storage` - добавить capabilities
  - [ ] Machine providers - добавить capabilities

#### 6.3 Создать `runtime/supply_router.lua`
- [ ] Заменить проверки `if provider.supports_batch` на:
  ```lua
  if provider.capabilities.batch then
    -- use batch limits
  end
  ```
- [ ] Реализовать логику маршрутизации:
  - [ ] `route_request(item, count, providers) -> provider_id`
  - [ ] `split_batch(count, capability) -> {batches...}`
  - [ ] `select_optimal_provider(item, providers, caps_filter)`
- [ ] Переместить batching логику из executor в router

#### 6.4 Удалить старые if-проверки
- [ ] Найти все `if provider.supports_X` в коде
- [ ] Заменить на `if provider.capabilities.X`
- [ ] Удалить дублирующиеся проверки из executor

#### 6.5 Тесты
- [ ] `tests/core/capability_spec.lua` - валидация capabilities
- [ ] `tests/runtime/supply_router_spec.lua` - маршрутизация по capabilities
- [ ] Contract тест: все providers имеют валидные capabilities
- [ ] Интеграционный тест: router корректно использует capabilities

---

## P3: Event System

### 7. Строгие Event Types

#### 7.1 Создать `core/events.lua`
- [ ] Определить каталог типов событий:
  ```lua
  Events = {
    TaskStarted = { task_id, provider_id, time },
    TaskCompleted = { task_id, result, duration },
    TaskFailed = { task_id, error_code, reason },
    StorageMutation = { storage_id, item, delta, balance },
    ResourceReserved = { item, count, requester_id },
    ResourceReleased = { item, count, requester_id },
    MachineAllocated = { machine_id, recipe },
    MachineFreed = { machine_id }
  }
  ```
- [ ] Добавить конструкторы для каждого типа:
  - [ ] Валидация обязательных полей
  - [ ] Добавление timestamp автоматически
  - [ ] Генерация event_id

#### 7.2 Создать `core/event_validator.lua`
- [ ] Реализовать валидацию событий:
  - [ ] `validate_event(event_type, data) -> boolean, error`
  - [ ] Проверка всех обязательных полей
  - [ ] Проверка типов значений
- [ ] Добавить schema для каждого типа события

#### 7.3 Обновить `runtime/event_bus.lua`
- [ ] Изменить `publish(event_type, data)` на `publish(event)`
- [ ] Добавить валидацию при публикации:
  ```lua
  function EventBus:publish(event)
    assert(Events[event.type], "Unknown event type")
    validate_event(event)
    -- publish
  end
  ```
- [ ] Обновить все вызовы `publish` в кодебазе

#### 7.4 Обновить издателей событий
- [ ] Executor - использовать `Events.TaskStarted`, etc.
- [ ] Storage providers - использовать `Events.StorageMutation`
- [ ] Machine allocator - использовать `Events.MachineAllocated`
- [ ] Заменить все "сырые" таблицы на typed events

#### 7.5 Улучшить подписчиков
- [ ] Обновить логи для использования структурированных событий
- [ ] Обновить визуализацию/трассировку
- [ ] Добавить type hints в обработчики событий

#### 7.6 Тесты
- [ ] `tests/core/events_spec.lua` - валидация типов событий
- [ ] `tests/core/event_validator_spec.lua` - проверка schema
- [ ] `tests/runtime/event_bus_spec.lua` - публикация typed events
- [ ] Интеграционный тест: весь flow генерирует валидные события

---

## Migration Strategy

### Фаза 1: Plan Graph (без breaking changes)
1. Создать `PlanGraph` и `scheduler` параллельно
2. Planner возвращает И список И граф (опционально)
3. Executor поддерживает оба режима
4. Тесты для нового пути
5. Миграция: переключить flag `use_plan_graph = true`

### Фаза 2: Capabilities (постепенно)
1. Добавить capabilities во все providers (опционально)
2. Supply router использует capabilities если есть, иначе fallback
3. Постепенно убрать fallback логику
4. Удалить старые if-проверки

### Фаза 3: Events (параллельная система)
1. Ввести typed events параллельно со старой системой
2. Поддерживать оба формата в event bus
3. Мигрировать издателей по одному
4. Мигрировать подписчиков
5. Удалить legacy поддержку

---

## Проверочный чек-лист перед началом

- [ ] Все существующие тесты проходят
- [ ] Создан feature branch для каждого улучшения
- [ ] Написаны тесты ДО реализации (TDD)
- [ ] Документация обновляется вместе с кодом
- [ ] Нет breaking changes без migration path

. Storage ≠ ResourceProvider (развести роли)

Проблема

Сейчас providers/resource/*, runtime/multi_storage, storage_manager и virtual_storage частично дублируют роли:

хранение данных

маршрутизация

async

ограничения

Улучшение: ввести явную модель

StorageBackend   — физическое хранилище (chest, memory, async)
StorageView      — транзакционный слой (begin/commit/rollback)
SupplyRouter     — только маршрутизация и batching

Новый слой
StorageBackend:
  get()
  get_async()
  get_batch_async()
  poll()
  collect()

StorageView:
  begin()
  snapshot()
  commit()
  rollback()


multi_storage становится координатором, а не «супер-хранилищем».

3. Унифицировать async-контракты (машины и склады)

Проблема

Машины: start → poll → collect

Склады: get_async → poll_request → collect_request

Похожие, но не одинаковые.

Улучшение

Ввести единый контракт AsyncHandle.

handle = provider:request(payload)

provider:poll(handle) -> RUNNING | DONE | FAILED
provider:collect(handle) -> result


Это позволит:

обрабатывать машины и склады одним кодом,

упростить executor,

упростить тесты параллелизма.


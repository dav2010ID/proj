Ниже полная, рабочая архитектура. Она масштабируется. Она разделяет планирование, ресурсы и машины. Основана на DFS с reserved.

---

## Общая схема

```
[ Planner (DFS) ]
        |
        v
[ Execution Plan ]
        |
        v
[ Executor ]
   |          |
   v          v
[ Resource ] [ Machine ]
[ Provider ] [ Provider ]
```

Цель. Планер ничего не знает про сундуки и машины. Он работает только с абстракциями.

---

## 1. Контракты интерфейсов

### ResourceProvider

Отвечает за предметы.

Обязанности:

* Учет доступного.
* Резервирование.
* Выдача предметов.
* Фиксация изменений.

Интерфейс:

```lua
ResourceProvider = {}

function ResourceProvider:get(itemKey) -> count end
function ResourceProvider:reserve(itemKey, count) -> bool end
function ResourceProvider:consume(itemKey, count) end
function ResourceProvider:rollback() end
function ResourceProvider:commit() end
```

Минимальная реализация. In memory слой поверх Create Stock.

---

### MachineProvider

Отвечает за выполнение рецептов.

Интерфейс:

```lua
MachineProvider = {}

function MachineProvider:canCraft(recipe) -> bool end
function MachineProvider:craft(recipe, times) -> bool end
```

Каждая машина это модуль.

* CraftingTableProvider
* CreateMechanicalCrafterProvider
* MixerProvider

---

## 2. Модель рецепта

```lua
Recipe = {
  id = "oak_planks",
  outputs = {
    { item = "minecraft:oak_planks", count = 4 }
  },
  inputs = {
    { item = "minecraft:oak_log", count = 1 }
  },
  machine = "crafting_table",
  priority = 10
}
```

Индекс:

```lua
recipesByOutput[itemKey] = { recipe1, recipe2 }
```

---

## 3. Планировщик (DFS + reserved)

### Контекст планирования

```lua
PlanContext = {
  resource = ResourceProvider,
  recipes = recipesByOutput,
  reserved = {},
  stack = {},        -- для детекта циклов
  plan = {}          -- список операций
}
```

---

### Вспомогательные функции

```lua
local function reservedCount(ctx, item)
  return ctx.reserved[item] or 0
end

local function addReserved(ctx, item, count)
  ctx.reserved[item] = reservedCount(ctx, item) + count
end
```

---

### Основная функция DFS

```lua
function planNeed(ctx, item, count)
  -- цикл
  if ctx.stack[item] then
    return false, "cycle"
  end

  local available = ctx.resource:get(item)
  local reserved = reservedCount(ctx, item)
  local use = math.min(count, math.max(0, available - reserved))

  if use > 0 then
    addReserved(ctx, item, use)
    table.insert(ctx.plan, {
      type = "supply",
      item = item,
      count = use
    })
  end

  local remain = count - use
  if remain == 0 then
    return true
  end

  local recipes = ctx.recipes[item]
  if not recipes then
    return false, "no_recipe"
  end

  ctx.stack[item] = true

  local recipe = selectRecipe(recipes)
  local out = recipe.outputs[1]
  local times = math.ceil(remain / out.count)

  -- сначала ингредиенты
  for _, input in ipairs(recipe.inputs) do
    local ok, err = planNeed(
      ctx,
      input.item,
      input.count * times
    )
    if not ok then
      ctx.stack[item] = nil
      return false, err
    end
  end

  table.insert(ctx.plan, {
    type = "craft",
    recipe = recipe,
    times = times
  })

  ctx.stack[item] = nil
  addReserved(ctx, item, out.count * times)

  return true
end
```

Ключевое:

* Сначала потребности.
* Потом операция.
* Reserved защищает от двойного расхода.

---

### Выбор рецепта

Минимально:

```lua
function selectRecipe(recipes)
  table.sort(recipes, function(a, b)
    return (a.priority or 0) > (b.priority or 0)
  end)
  return recipes[1]
end
```

---

## 4. План выполнения

Структура операций:

```lua
{
  { type = "supply", item = "...", count = 5 },
  { type = "craft", recipe = Recipe, times = 2 }
}
```

Порядок уже корректный. Это postorder.

---

## 5. Executor

```lua
function execute(plan, resource, machines)
  for _, step in ipairs(plan) do
    if step.type == "supply" then
      resource:consume(step.item, step.count)

    elseif step.type == "craft" then
      local provider = machines[step.recipe.machine]
      if not provider then return false, "no_machine" end
      local ok = provider:craft(step.recipe, step.times)
      if not ok then return false, "craft_failed" end
    end
  end
  resource:commit()
  return true
end
```

---

## 6. Реализация провайдеров

### ResourceProvider поверх Create Stock

* `get` читает агрегацию
* `consume` формирует requestFiltered
* `commit` отправляет все запросы
* `rollback` очищает очередь

Важно. Списание логическое происходит в планере. Физическое в executor.

---

### MachineProvider как плагины

```lua
CraftingTableProvider = {}

function CraftingTableProvider:canCraft(recipe)
  return recipe.machine == "crafting_table"
end

function CraftingTableProvider:craft(recipe, times)
  for i = 1, times do
    -- разложить ингредиенты
    -- дождаться результата
  end
  return true
end
```

Регистрация:

```lua
machines = {
  crafting_table = CraftingTableProvider,
  mechanical_crafter = MechanicalCrafterProvider
}
```



---


0) База проекта

 Создать структуру файлов:

 main.lua

 types.lua

 recipes.lua

 planner.lua

 executor.lua

 providers/resource/base.lua

 providers/resource/memory.lua

 providers/resource/create_stock.lua

 providers/machine/base.lua

 providers/machine/crafting_table.lua

 providers/machine/mechanical_crafter.lua (опционально)

 util/log.lua

 util/itemkey.lua

 В main.lua сделать один вход: craft(itemName, count).

1) Типы и нормализация предметов

 Определить формат ItemKey:

 name обязательный


 Написать util/itemkey.lua:

 normalize(stackOrName) -> itemKey

 same(a,b) -> bool

 toString(itemKey) -> string

2) Рецепты

 Определить структуру Recipe:

 id, inputs, outputs, machine, priority

 Написать recipes.lua:

 add(recipe)

 buildIndex() -> recipesByOutput

 getRecipesFor(itemKey) -> list

 Добавить тестовые рецепты:

 бревно -> доски

 доски -> палки

 палки + доски -> верстак (пример с 2 ингредиентами)

3) ResourceProvider

 Определить интерфейс providers/resource/base.lua:

 get(itemKey)

 queueConsume(itemKey, count) или consume(itemKey, count)

 commit()

 rollback()

 Реализовать providers/resource/memory.lua:

 хранит available[itemKey]

 get читает

 consume уменьшает локально

 commit пустой

 Добавить “виртуальные резервы” в планере, не в провайдере.

4) Planner (DFS + reserved)

 Написать planner.lua:

 plan(targetItemKey, targetCount, recipesByOutput, resourceProvider) -> (ok, planOrErr)

 Реализовать:

 reserved таблица

 stack для циклов

 selectRecipe(recipes) по priority

 planNeed(item, count) как DFS postorder

 Проверки:

 если нет рецепта и нет запаса -> no_recipe_or_stock

 цикл -> cycle

 Добавить вывод плана в лог:

 печать supply и craft шагов

5) Executor

 Написать executor.lua:

 execute(plan, resourceProvider, machineRegistry) -> (ok, err)

 Реализовать:

 шаг supply: вызвать resourceProvider:consume(item,count)

 шаг craft: найти machineRegistry[recipe.machine] и вызвать :craft(recipe,times)

 на успехе resourceProvider:commit()

 на ошибке resourceProvider:rollback()

6) MachineProvider и модульное подключение

 Определить интерфейс providers/machine/base.lua:

 canCraft(recipe) -> bool (опционально)

 craft(recipe, times) -> bool, err

 Сделать providers/machine/crafting_table.lua (пока заглушка):

 craft просто print и return true

 Реестр машин в main.lua:

 machines = { crafting_table = CraftingTableProvider }

 подключение модулей через require

7) Интеграция с Create Stock Ticker (когда логика стабилизируется)

 Реализовать providers/resource/create_stock.lua:

 scanStock(includeTags=true) и построение available

 очередь запросов pending[itemKey]+=count

 commit() делает один или несколько requestFiltered(address, ...)

 обработка частичных выдач и повторов

 Решить адрес получателя и куда приходят предметы.

8) Реальная машина (когда ресурсы работают)

 Реализовать реальный crafting_table.lua:

 взять ингредиенты из буфера

 разложить в 3x3

 забрать результат

 обработать остатки и контейнеры

 Добавить таймауты и проверки инвентаря.

9) Надежность

 Логи:

 info, warn, error

 лог плана и факта выполнения

 Реплан при ошибке:

 если craft_failed из-за нехватки входов -> пересканировать ресурс и перепланировать недостающее

 Ограничение глубины DFS, защита от бесконечного роста плана.

10) UX

 Команда:

 craft <item> <count>

 plan <item> <count> печатает план без исполнения

 Визуализация дерева:

 печать с отступами по глубине (потом)
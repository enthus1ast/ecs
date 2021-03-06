import tables, hashes, intsets

type
  Entity* = uint32
  ComponentStore* = TableRef[Entity, Component]
  Registry* = ref object
    entityLast: Entity
    validEntities: IntSet
    invalideEntities: IntSet
    components: TableRef[Hash, ComponentStore]
  Component* = ref object of RootObj

proc newRegistry*(): Registry =
  result = Registry()
  result.entityLast = 0
  result.components = newTable[Hash, ComponentStore]()

proc newEntity*(reg: Registry): Entity =
  reg.entityLast.inc
  reg.validEntities.incl((int) reg.entityLast)
  return reg.entityLast

proc addComponent*[T](reg: Registry, ent: Entity, comp: T) =
  let componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    reg.components[componentHash] = newTable[Entity, Component]()
  reg.components[componentHash][ent] = comp

proc getComponent*[T](reg: Registry, ent: Entity): T =
  let componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    raise newException(ValueError, "No store for this component: " & $(T))
  if not reg.validEntities.contains((int)ent):
    raise newException(ValueError, "Entity " & $ent & " is invalidated!")
  if not reg.components[componentHash].hasKey(ent):
    raise newException(ValueError, "Entity " & $ent & " has no component:" & $(T))
  return (T) reg.components[componentHash][ent]

proc getComponent*(reg: Registry, ent: Entity, T: typedesc): T =
  ## convenient proc to enable this:
  ##  reg.getComponent(FooComponent, ent)
  return getComponent[T](reg, ent)

proc removeComponent*[T](reg: Registry, ent: Entity) =
  let componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    raise newException(ValueError, "No store for this component: " & $(T))
  if not reg.components[componentHash].hasKey(ent):
    return
  reg.components[componentHash].del(ent)

proc removeComponent*(reg: Registry, ent: Entity, T: typedesc) =
  ## convenient proc to enable this:
  ##  reg.removeComponent(FooComponent, ent)
  removeComponent[T](reg, ent)

proc hasComponent[T](reg: Registry, ent: Entity): bool =
  let componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    return false # when no store exists entity cannot have the component
  if not reg.validEntities.contains((int)ent):
    return false
  return reg.components[componentHash].hasKey(ent)

proc hasComponent*(reg: Registry, ent: Entity, T: typedesc): bool =
  ## convenient proc to enable this:
  ##  reg.hasComponent(FooComponent, ent)
  hasComponent[T](reg, ent)

proc invalidateEntity*(reg: Registry, ent: Entity) =
  ## Invalidates an entity, this can be called in a loop, make sure you call "cleanup()" once in a while to remove invalidated entities
  reg.validEntities.excl(int ent)
  reg.invalideEntities.incl(int ent)

proc destroyEntity*(reg: Registry, ent: Entity) =
  ## removes all registered components for this entity
  ## this cannot be called while iterating over components, use invalidateEntity for this
  for store in reg.components.values:
    store.del(ent)
  reg.validEntities.excl(int ent)

proc cleanup*(reg: Registry) =
  ## removes all invalidated entities
  ## call this periodically.
  for ent in reg.invalideEntities:
    reg.destroyEntity((Entity) ent)
  reg.invalideEntities.clear()

proc destroyAll*(reg: Registry) =
  ## removes all entities
  let buf = reg.validEntities # buffer needet because iterating while deleting does not work
  for ent in buf:
    reg.destroyEntity((Entity) ent)

iterator entities*(reg: Registry, T: typedesc, invalidate = false): Entity =
  let componentHash = ($T).hash()
  if reg.components.hasKey(componentHash):
    # raise newException(ValueError, "No store for this component: " & $(T)) # TODO raise?
    for ent in reg.components[componentHash].keys:
      if invalidate or reg.validEntities.contains((int)ent):
        yield ent

proc getStore*(reg: Registry, T: typedesc): ComponentStore =
  let componentHash = ($T).hash()
  return reg.components[componentHash]

##########################################
# Tests
##########################################
when isMainModule:
  import unittest
  suite "ecs":
    setup:
      var reg = newRegistry()
      var e1 = reg.newEntity()
      type
        Health = ref object of Component
          health: int
          maxHealth: int
        Mana = ref object of Component
          mana: int
          maxMana: int
        Kaka = ref object of Component ## This is never used
          mana: int
          maxMana: int
    test "basic":
      reg.addComponent(e1, Health(health: 10, maxHealth: 100))
      reg.addComponent(e1, Mana(mana: 10, maxMana: 100))
      block:
        var h1 = reg.getComponent(e1, Health)
        check h1.health == 10
        check h1.maxHealth == 100
      block:
        var h1 = getComponent[Health](reg, e1)
        h1.health = 20
        check reg.getComponent(e1, Health).health == 20
      check reg.hasComponent(e1, Health) == true
      reg.removeComponent(e1, Health)
      check reg.hasComponent(e1, Health) == false
    test "not there":
      doAssertRaises(ValueError):
        discard getComponent[Kaka](reg, e1)
      check reg.hasComponent(e1, Kaka) == false
    test "destroy entity":
      reg = newRegistry()
      var e2 = reg.newEntity()
      check reg.validEntities.len == 1
      reg.addComponent(e2, Health(health: 10, maxHealth: 100))
      reg.addComponent(e2, Mana(mana: 10, maxMana: 100))
      check reg.hasComponent(e2, Health) == true
      check reg.hasComponent(e2, Mana) == true
      reg.destroyEntity(e2)
      check reg.validEntities.len == 0
      check reg.hasComponent(e2, Health) == false
      check reg.hasComponent(e2, Mana) == false
    test "iter":
      block:
        reg = newRegistry()
        var e1 = reg.newEntity()
        var e2 = reg.newEntity()
        reg.addComponent(e1, Health(health: 10, maxHealth: 100))
        reg.addComponent(e2, Health(health: 10, maxHealth: 100))
        reg.addComponent(e2, Mana(mana: 10, maxMana: 100))
        block:
          var idx1 = 0
          for ent in reg.entities(Health):
            idx1.inc
          check idx1 == 2
        block:
          var idx2 = 0
          for ent in reg.entities(Mana):
            idx2.inc
          check idx2 == 1
    test "destroy all":
      block:
        reg = newRegistry()
        var e1 = reg.newEntity()
        var e2 = reg.newEntity()
        reg.addComponent(e1, Health(health: 10, maxHealth: 100))
        reg.addComponent(e2, Health(health: 10, maxHealth: 100))
        reg.addComponent(e2, Mana(mana: 10, maxMana: 100))
        check reg.getStore(Health).len == 2
        check reg.getStore(Mana).len == 1
        reg.destroyAll()
        check reg.validEntities.len == 0
        check reg.getStore(Health).len == 0
        check reg.getStore(Mana).len == 0
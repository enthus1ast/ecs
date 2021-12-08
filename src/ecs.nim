import tables, hashes, intsets

type
  Entity* = uint32
  ComponentStore* = TableRef[Entity, Component]
  ComponentDestructor* = proc (reg: Registry, entity: Entity, comp: Component)  #{.closure.}
  ComponentDestructors* = TableRef[Hash, ComponentDestructor]
  Registry* = ref object
    entityLast*: Entity
    validEntities*: IntSet
    invalideEntities*: IntSet
    components: TableRef[Hash, ComponentStore]
    componentDestructors: ComponentDestructors
  ComponentObj* = object of RootObj
  Component* = ref object of RootObj

proc newRegistry*(): Registry =
  result = Registry()
  result.entityLast = 0
  result.components = newTable[Hash, ComponentStore]()
  result.componentDestructors = newTable[Hash, ComponentDestructor]()

proc newEntity*(reg: Registry): Entity {.inline.} =
  reg.entityLast.inc
  reg.validEntities.incl((int) reg.entityLast)
  return reg.entityLast

proc addComponentDestructor*[T](reg: Registry, comp: typedesc[T], cb: ComponentDestructor) =
  ## Registers a destructor which gets called on component destruction
  ## ComponentDestructor can be closures eg:
  ## .. code-block:: nim
  ##  type CObj = object
  ##    ss: string
  ##  var cobj = CObj(ss: "foo")
  ##  proc healthDestructor(reg: Registry, comp: Component) =
  ##    echo cobj.ss # <- bound object
  ##    echo "In health destructor:", $(Health(comp).health)
  ##  reg.addComponentDestructor(Health, healthDestructor) # <- register destructor
  ##  reg.removeComponent(ee, Health) # <- calls the destructor then removes the component
  let componentHash = ($T).hash()
  reg.componentDestructors[componentHash] = cb

proc addComponent*[T](reg: Registry, ent: Entity, comp: T) {.inline.} =
  let componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    reg.components[componentHash] = newTable[Entity, Component]()
  reg.components[componentHash][ent] = comp

proc getComponent*[T](reg: Registry, ent: Entity): T {.inline.} =
  let componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    raise newException(ValueError, "No store for this component: " & $(T))
  if not reg.validEntities.contains((int)ent):
    raise newException(ValueError, "Entity " & $ent & " is invalidated!")
  if not reg.components[componentHash].hasKey(ent):
    raise newException(ValueError, "Entity " & $ent & " has no component:" & $(T))
  return (T) reg.components[componentHash][ent]

proc getComponent*(reg: Registry, ent: Entity, T: typedesc): T {.inline.} =
  ## convenient proc to enable this:
  ##  reg.getComponent(FooComponent, ent)
  return getComponent[T](reg, ent)

proc removeComponent*[T](reg: Registry, ent: Entity) {.inline.} =
  ## removes a component, also calls it destructor
  ## previously registered with `addComponentDestructor`
  let componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    raise newException(ValueError, "No store for this component: " & $(T))
  if not reg.components[componentHash].hasKey(ent):
    return
  if reg.componentDestructors.hasKey(componentHash):
    let dest = reg.componentDestructors[componentHash] # (reg, reg.components[componentHash][ent])
    dest(reg, ent, reg.components[componentHash][ent])
  reg.components[componentHash].del(ent)

proc removeComponent*(reg: Registry, ent: Entity, T: typedesc) {.inline.} =
  ## convenient proc to enable this:
  ##  reg.removeComponent(FooComponent, ent)
  removeComponent[T](reg, ent)

proc hasComponent[T](reg: Registry, ent: Entity): bool {.inline.} =
  let componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    return false # when no store exists entity cannot have the component
  if not reg.validEntities.contains((int)ent):
    return false
  return reg.components[componentHash].hasKey(ent)

proc hasComponent*(reg: Registry, ent: Entity, T: typedesc): bool {.inline.} =
  ## convenient proc to enable this:
  ##  reg.hasComponent(FooComponent, ent)
  hasComponent[T](reg, ent)

proc invalidateEntity*(reg: Registry, ent: Entity) {.inline.} =
  ## Invalidates an entity, this can be called in a loop,
  ## make sure you call `cleanup()` once in a while to remove invalidated entities
  ## This does NOT call the Component destructor immediately, `cleanup` will
  reg.validEntities.excl(int ent)
  reg.invalideEntities.incl(int ent)

proc invalidateAll*(reg: Registry, filter: IntSet = initIntSet()) {.inline.} =
  for ent in reg.validEntities:
    if not filter.contains(ent):
      reg.invalidateEntity(ent.Entity)

proc destroyEntity*(reg: Registry, ent: Entity) {.inline.} =
  ## removes all registered components for this entity
  ## this cannot be called while iterating over components, use invalidateEntity for this
  for compHash, store in reg.components.pairs:
    if reg.componentDestructors.hasKey(compHash):
      var dest = reg.componentDestructors[compHash]
      dest(reg, ent, store[ent])
    store.del(ent)
  reg.validEntities.excl(int ent)

proc cleanup*(reg: Registry) {.inline.} =
  ## removes all invalidated entities
  ## call this periodically.
  ## Note: This calls the component destructors (if any)
  ## of previously invalidated objects!
  for ent in reg.invalideEntities:
    reg.destroyEntity((Entity) ent)
  reg.invalideEntities.clear()

proc destroyAll*(reg: Registry) {.inline.} =
  ## removes all entities, calls the component destructors (if any)
  let buf = reg.validEntities # buffer needed because iterating while deleting does not work
  for ent in buf:
    reg.destroyEntity((Entity) ent)

iterator entities*(reg: Registry, T: typedesc, invalidate = false): Entity {.inline.} =
  let componentHash = ($T).hash()
  if reg.components.hasKey(componentHash):
    # raise newException(ValueError, "No store for this component: " & $(T)) # TODO raise?
    for ent in reg.components[componentHash].keys:
      if invalidate or reg.validEntities.contains((int)ent):
        yield ent

proc getStore*(reg: Registry, T: typedesc): ComponentStore {.inline.} =
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
        ManaObj = object of Component
          mana: int
          maxMana: int
        Mana = ref ManaObj
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
    test "modify":
      block:
        reg = newRegistry()
        var e1 = reg.newEntity()
        reg.addComponent(e1, Health(health: 10, maxHealth: 100))
        reg.getComponent(e1, Health).health = 50
        check reg.getComponent(e1, Health).health == 50
    test "destructor":
      ## This test should test how a destructor could be called by the ecs.
      ## But this does not work properly yet.
      ## The feature that the ecs SHOULD have is:
      ## getComponent() should return a modifiable version of the componet (ref type)
      ##   BUT should also call a destructor when destroyed. Eg:
      ##   A component like:
      ## ComplexComponent = object of Component
      ##   anEntity: Entity
      ##   anotherEntity: Entity
      ## should (maybe) remove `anEntity` and `anotherEntity` when removed.
      block:
        var wasDestructed = false
        proc `=destroy`(comp: var ManaObj) = # Must be ManaObj (see above in type section)
          echo "DESTRUCT MANA WAS:", comp.mana
          wasDestructed = true
        proc innerProc() =
          reg = newRegistry()
          var e1 = reg.newEntity()
          reg.addComponent(e1, Mana(mana: 123))
          check reg.getComponent(e1, Mana).mana == 123
          reg.removeComponent(e1, Mana)

        ## Must be written multiple times that something happens, strange
        ## TODO test if this is the same issue: https://github.com/nim-lang/Nim/issues/15629
        innerProc()
        innerProc() ## second time, needet for default gc to make the test true
        GC_fullCollect() # to force the calling of destructor in normal gc mode
        check wasDestructed == true
    test "destructorInternalExplicitly":
      reg = newRegistry()
      var ee = reg.newEntity()
      reg.addComponent(ee, Health(health: 123))
      type CObj = object
        ss: string
        cnt: int
      var cobj = CObj(ss: "foo")
      proc healthDestructor(reg: Registry, ent: Entity,  comp: Component) =
        echo cobj.ss # <- bound object
        cobj.cnt.inc
        echo "In health destructor destructorInternalExplicitly:", $ent, " ", $(Health(comp).health)
      reg.addComponentDestructor(Health, healthDestructor)
      reg.removeComponent(ee, Health)
      check cobj.cnt == 1
    test "destructorInternalImplicitly":
      reg = newRegistry()
      var ee = reg.newEntity()
      reg.addComponent(ee, Health(health: 321))
      type CObj = ref object
        ss: string
        cnt: int
      var cobj = CObj(ss: "foo", cnt: 0)
      proc healthDestructor(reg: Registry, ent: Entity, comp: Component) =
        echo cobj.ss # <- bound object
        cobj.cnt.inc
        echo "In health destructor destructorInternalImplicitly: ", $ent, " ", $(Health(comp).health)
      reg.addComponentDestructor(Health, healthDestructor)
      reg.destroyEntity(ee)
      reg.cleanup()
      check cobj.cnt == 1
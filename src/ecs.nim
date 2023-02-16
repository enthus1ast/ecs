## A simple Entity Component System.
## With event system.


# ----------------------- Implementation
import tables, hashes, intsets, std/deques, macros
export tables, intsets

type
  Entity* = int
  ComponentStore* = TableRef[Entity, Component]
  ComponentDestructor* = proc (reg: Registry, entity: Entity, comp: Component) {.gcsafe.}  #{.closure.}
  ComponentDestructors* = TableRef[Hash, ComponentDestructor]
  Registry* = ref object
    entityLast*: Entity
    validEntities*: IntSet
    invalideEntities*: IntSet
    components: TableRef[Hash, ComponentStore]
    componentDestructors: ComponentDestructors
    ev: Table[Hash, IntSet] ## container for events
    # evs: Deque[proc ()] ## the storage for triggerLater closures
    removeComponentLaterStore: seq[tuple[ent: Entity, tyh: Hash]]
  ComponentObj* = object of RootObj
  Component* = ref object of RootObj


func newRegistry*(): Registry =
  ## Returns a new `Registry` this is the main object of the ECS
  result = Registry()
  result.entityLast = 0
  result.components = newTable[Hash, ComponentStore]()
  result.componentDestructors = newTable[Hash, ComponentDestructor]()


func len*(reg: Registry): int =
  return reg.validEntities.len


func isValid*(reg: Registry, ent: Entity): bool {.inline.} =
  return reg.validEntities.contains(ent)

func newEntity*(reg: Registry, ent = -1): Entity {.inline.} =
  ## Creates a new entity
  runnableExamples():
    var reg = newRegistry()
    var ent = reg.newEntity()
  if ent == -1:
    reg.entityLast.inc
  else:
    reg.entityLast = Entity(ent)
  reg.validEntities.incl(reg.entityLast)
  return reg.entityLast
template newEntity*(ent = -1): Entity =
  newEntity(reg, ent)


proc addComponentDestructor*[T](reg: Registry, comp: typedesc[T], cb: ComponentDestructor) =
  ## Registers a destructor which gets called on component destruction.
  ## ComponentDestructor can be a closure.
  runnableExamples():
    type
      Health = ref object of Component
        health: int
        maxHealth: int
    var reg = newRegistry()
    var ee = reg.newEntity()
    reg.addComponent(ee, Health(health: 100, maxHealth: 200))
    type CObj = object # declare a bound obj, that is available in the callback
      ss: string
    var cobj = CObj(ss: "foo")
    proc healthDestructor(reg: Registry, ent: Entity, comp: Component) {.gcsafe.} =
      echo cobj.ss # <- bound object
      echo "In health destructor:", $(Health(comp).health)
    reg.addComponentDestructor(Health, healthDestructor) # <- register destructor
    reg.removeComponent(ee, Health) # <- calls the destructor then removes the component

  const componentHash = ($T).hash()
  reg.componentDestructors[componentHash] = cb
template addComponentDestructor*[T](comp: typedesc[T], cb: ComponentDestructor) =
  addComponentDestructor(reg, comp, cb)


func addComponent*[T](reg: Registry, ent: Entity, comp: T) {.inline.} =
  ## Registers a new component with the entity
  runnableExamples:
    var reg = newRegistry()
    var ent = reg.newEntity()
    type Health = ref object of Component
      health: int
    var compHealth = Health(health: 100)
    reg.addComponent(ent, compHealth)

  const componentHash = ($T).hash()
  if not reg.components.hasKey(componentHash):
    reg.components[componentHash] = newTable[Entity, Component]()
  reg.components[componentHash][ent] = comp
template addComponent*[T](ent: Entity, comp: T) =
  addComponent(reg, ent, comp)


template `:=`*[T](ent: Entity, comp: T) =
  ## addComponent but uses global reg
  reg.addComponent(ent, comp)

func getComponent*(reg: Registry, ent: Entity, ty: typedesc): ty {.inline.} =
  ## get a component from an entity
  runnableExamples:
    var reg = newRegistry()
    var ent = reg.newEntity()
    type Health = ref object of Component
      health: int
    reg.addComponent(ent, Health(health: 100))
    var compHealth = reg.getComponent(ent, Health)

  const componentHash = ($ty.type).hash()
  when not defined(release):
    if not reg.components.hasKey(componentHash):
      raise newException(ValueError, "No store for this component: " & $(ty.type))
    if not reg.validEntities.contains(ent):
      raise newException(ValueError, "Entity " & $ent & " is invalidated!")
    if not reg.components[componentHash].hasKey(ent):
      raise newException(ValueError, "Entity " & $ent & " has no component:" & $(ty.type))
  return (ty) reg.components[componentHash][ent]
template getComponent*(ent: Entity, ty: typedesc): untyped =
  getComponent(reg, ent, ty)
template `[]`*(ent: Entity, ty: typedesc): untyped =
  getComponent(reg, ent, ty)


proc removeComponent*(reg: Registry, ent: Entity, ty: typedesc | Hash) {.inline.} =
  ## removes a component, also calls it destructor
  ## previously registered with `addComponentDestructor`
  when ty is typedesc:
    const componentHash = ($ty).hash()
  else:
    let componentHash = ty
  when not defined(release):
    if not reg.components.hasKey(componentHash):
      raise newException(ValueError, "No store for this component: " & $(ty))
  if not reg.components[componentHash].hasKey(ent):
    return
  if reg.componentDestructors.hasKey(componentHash):
    let dest = reg.componentDestructors[componentHash] # (reg, reg.components[componentHash][ent])
    dest(reg, ent, reg.components[componentHash][ent])
  reg.components[componentHash].del(ent)
template removeComponent*(ent: Entity, ty: typedesc | Hash) =
  removeComponent(reg, ent, ty)


proc removeComponentLater*(reg: Registry, ent: Entity, ty: typedesc) {.inline.} =
  ## Enques a component for later destruction (through reg.update)
  # reg.
  discard
  const componentHash = hash($ty)
  reg.removeComponentLaterStore.add( (ent, componentHash) )
template removeComponentLater*(ent: Entity, ty: typedesc) =
  removeComponentLater(reg, ent, ty)


func hasComponent*(reg: Registry, ent: Entity, ty: typedesc): bool {.inline.} =
  const componentHash = ($ty).hash()
  if not reg.components.hasKey(componentHash):
    return false # when no store exists entity cannot have the component
  if not reg.validEntities.contains((int)ent):
    return false
  return reg.components[componentHash].hasKey(ent)
template hasComponent*(ent: Entity, ty: typedesc): bool =
  hasComponent(reg, ent, ty)


func invalidateEntity*(reg: Registry, ent: Entity) {.inline.} =
  ## Invalidates an entity, this can be called in a loop,
  ## make sure you call `cleanup()` once in a while to remove invalidated entities
  ## This does NOT call the Component destructor immediately, `cleanup` will
  reg.validEntities.excl(ent)
  reg.invalideEntities.incl(ent)
template invalidateEntity*(ent: Entity) =
  invalidateEntity(reg, ent)



func invalidateAll*(reg: Registry, filter: IntSet = initIntSet()) {.inline.} =
  ## invalidates all entities, except the ones in `filter`
  for ent in reg.validEntities:
    if not filter.contains(ent):
      reg.invalidateEntity(ent.Entity)
template invalidateAll*(filter: IntSet = initIntSet()) =
  invalidateAll(reg, filter)


proc destroyEntity*(reg: Registry, ent: Entity) {.inline, gcsafe.} =
  ## removes all registered components for this entity
  ## this cannot be called while iterating over components, use invalidateEntity for this
  for compHash, store in reg.components.pairs:
    if store.hasKey(ent):
      if reg.componentDestructors.hasKey(compHash):
        var dest = reg.componentDestructors[compHash]
        dest(reg, ent, store[ent])
      store.del(ent)
  reg.validEntities.excl(ent)
template destroyEntity*(ent: Entity) =
  destroyEntity(reg, ent)


proc cleanup*(reg: Registry) {.inline.} =
  ## Removes all invalidated entities.
  ## Call this periodically.
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
  const componentHash = ($T).hash()
  if reg.components.hasKey(componentHash):
    # raise newException(ValueError, "No store for this component: " & $(T)) # TODO raise?
    for ent in reg.components[componentHash].keys:
      if invalidate or reg.validEntities.contains(ent):
        yield ent
template entities*(T: typedesc, invalidate = false): Entity =
  entities(reg, T, invalidate)



iterator entitiesWithComp*(reg: Registry, T: typedesc): tuple[ent: Entity, comp: T] {.inline.} =
  const componentHash = ($T).hash()
  if reg.components.hasKey(componentHash):
    # raise newException(ValueError, "No store for this component: " & $(T)) # TODO raise?
    for ent, comp in reg.components[componentHash]:
      if reg.validEntities.contains((int)ent):
        yield (ent: ent, comp: T(comp))
template entitiesWithComp*(T: typedesc): tuple[ent: Entity, comp: T] =
  entitiesWithComp(reg, T)



iterator entitiesWithComp*[A, B](reg: Registry, aa: typedesc[A], bb: typedesc[B]): tuple[ent: Entity, a: A, b: B] {.inline.} =
  for ent, compA in reg.entitiesWithComp(A):
    if reg.hasComponent(ent, bb):
      yield (ent: ent, a: compA, b: reg.getComponent(ent, B))
template entitiesWithComp*[A, B](aa: typedesc[A], bb: typedesc[B]): tuple[ent: Entity, a: A, b: B] =
  entitiesWithComp(reg, aa, bb)



iterator entitiesWithComp*[A, B, C](reg: Registry, aa: typedesc[A], bb: typedesc[B], cc: typedesc[C]): tuple[ent: Entity, a: A, b: B, c: C] {.inline.} =
  for ent, compA in reg.entitiesWithComp(A):
    if reg.hasComponent(ent, bb) and reg.hasComponent(ent, cc):
      yield (ent: ent, a: compA, b: reg.getComponent(ent, B), c: reg.getComponent(ent, C))
template entitiesWithComp*[A, B, C](aa: typedesc[A], bb: typedesc[B], cc: typedesc[C]): tuple[ent: Entity, a: A, b: B, c: C] =
  entitiesWithComp(reg, aa, bb, cc)


proc getStore*(reg: Registry, T: typedesc): ComponentStore {.inline.} =
  const componentHash = ($T).hash()
  return reg.components[componentHash]
template getStore*(T: typedesc): ComponentStore =
  getStore(reg, T)


# ### The event system
proc connect*(reg: Registry, ty: typedesc, cb: proc (ev: ty.type)) =
  ## Connect a proc to a event
  runnableExamples:
    var reg = newRegistry()
    type
      MyEvent = object
        hihi: string
    var boundObj = "foo"
    proc cbMyEvent(ev: MyEvent) =
      echo "my event was triggered", ev.hihi
      echo boundObj # events can be closures!
    reg.connect(MyEvent, cbMyEvent)

  const typehash = hash($ty)
  if not reg.ev.hasKey(typehash):
    reg.ev[typehash] = initIntSet()
  reg.ev[typehash].incl cast[int](rawProc cb)
template connect*(ty: typedesc, cb: proc (ev: ty.type)) =
  connect(reg, ty, cb)


proc disconnect*(reg: Registry, ty: typedesc, cb: pointer) =
  ## Disconnect a proc from a event
  runnableExamples:
    var reg = newRegistry()
    type
      MyEvent = object
    proc cbMyEvent(ev: MyEvent) =
      discard
    reg.connect(MyEvent, cbMyEvent)
    reg.disconnect(MyEvent, cbMyEvent)

  const typehash = hash($ty.type)
  if not reg.ev.hasKey(typehash): return
  reg.ev[typehash].excl cast[int](cb)
template disconnect*(ty: typedesc, cb: pointer) =
  disconnect(reg, ty, cb)


proc disconnectAll*(reg: Registry, ty: typedesc) =
  ## Disconnect all procs from a event
  const typehash = hash($ty.type)
  if not reg.ev.hasKey(typehash): return
  reg.ev[typehash].clear()
template disconnectAll*(ty: typedesc) =
  disconnectAll(reg, ty)


proc trigger*(reg: Registry, ev: auto) {.gcsafe.} =
  ## Triggers all the handlers bound for an event immediately!
  ## If this is called from a system, i currently cannot
  ## remove its component, since we iterate over them... # TODO
  const typehash = hash($ev.type)
  if not reg.ev.hasKey(typehash): return
  for pcb in reg.ev[typehash]:
    type pp = proc (ev: ev.type) {.nimcall, gcsafe.}
    cast[pp](pcb)(ev)
template trigger*(ev: auto) =
  trigger(reg, ev)


# TODO does not work because of: Error: unhandled exception: field 'sym' is not accessible for type 'TNode' using 'kind = nkClosure' [FieldDefect]
# proc triggerLater*(reg: Registry, ev: auto) =
#   ## Enqeues an event to be triggered on reg.update()
#   const typehash = hash($ev.type)
#   if not reg.ev.hasKey(typehash): return
#   # reg.evs[typehash].addLast(ev)
#   type ppi = proc (ev: ev.type) {.nimcall.}
#   for pcbb in reg.ev[typehash]:
#     proc clos() {.closure.} =
#       cast[ppi](pcbb)(ev)
#     addLast(reg.evs, clos)


proc update*(reg: Registry) =
  ##  - Deletes invalidated entities
  ##  - Triggers encqued procs
  reg.cleanup() # cleanup invalidated entities
  for (ent, tyh) in reg.removeComponentLaterStore:
    reg.removeComponent(ent, tyh)

  # for clos in reg.evs:
  #   cast[proc () {.nimcall.}](clos)()


# #########################################
# Global Example
# #########################################
runnableExamples:

  var reg = newRegistry()

  type
    Health = ref object of Component
      health: int
      maxHealth: int
      dead: bool
    Regeneration = ref object of Component
      healthRegen: int
    Poisoned = ref object of Component
      poisonStrength: int
    Corpse = ref object of Component

  var entPlayer = reg.newEntity() # a new Entity, store this and move this around.
  reg.addComponent(entPlayer, Health(health: 50, maxHealth: 100))
  reg.addComponent(entPlayer, Regeneration(healthRegen: 2))

  var entPlayer2 = reg.newEntity() # a new Entity, store this and move this around.
  reg.addComponent(entPlayer2, Health(health: 50, maxHealth: 100))
  reg.addComponent(entPlayer2, Poisoned(poisonStrength: 1))

  var entPlayer3 = reg.newEntity() # a new Entity, store this and move this around.
  reg.addComponent(entPlayer3, Health(health: 50, maxHealth: 100))
  reg.addComponent(entPlayer3, Regeneration(healthRegen: 5))
  reg.addComponent(entPlayer3, Poisoned(poisonStrength: 10))

  # Events example
  type
    EvDied = object
      ent: Entity

  # The benefit of of Events is that various parts
  # of your application or game, can connect to
  # an event. The various parts are therefore decoupled and can be disabled or added easily
  block: ## "ConsoleSubsystem.nim"
    proc cbDied(ev: EvDied) =
      echo "entity died:", ev.ent
      var compHealth = reg.getComponent(ev.ent, Health)
      compHealth.dead = true # later we will also remove the component
      # remove the `Health` component upon dead (as an example)
      reg.removeComponentLater(ev.ent, Health) # will later be removed on reg.update()
      echo "make this entity to a corpse"
      reg.addComponent(ev.ent, Corpse())
    reg.connect(EvDied, cbDied) # connect a callback to this event

  block: ## "SoundSubsystem.nim"
    proc cbDied(ev: EvDied) =
      echo "entity died, <PLAY A SOUND>:", ev.ent
    reg.connect(EvDied, cbDied) # connect a callback to this event

  proc systemHealth(reg: Registry) =
    for (ent, compHealth) in reg.entitiesWithComp(Health):
      if compHealth.dead: continue
      echo ent, ": ", compHealth[]
      if compHealth.health <= 0:
        reg.trigger(EvDied(ent: ent)) # Triggers the EvDied event handlers
        # reg.triggerLater(Ev)

  proc systemPoison(reg: Registry) =
    for (ent, compPoison, compHealth) in reg.entitiesWithComp(Poisoned, Health):
      if not compHealth.dead:
        compHealth.health -= compPoison.poisonStrength

  proc systemRegen(reg: Registry) =
    # regenerate health over time
    for (ent, compRegeneration, compHealth) in reg.entitiesWithComp(Regeneration, Health):
      if not compHealth.dead:
        compHealth.health += compRegeneration.healthRegen
        if compHealth.health > compHealth.maxHealth:
          compHealth.health = compHealth.maxHealth

  proc systemCorpse(reg: Registry) =
    ## A system that just prints out the corpse count (if any)
    try:
      let corpses = reg.getStore(Corpse).len
      if corpses == 1:
        echo "Only one dead body, nothing special..."
      elif corpses > 1:
        echo "Dead bodies everywhere: ", corpses
    except:
      discard # it could be that we do not have a store for corpses yet... # TODO ?

  var limitExecution = 60
  while true: ## games main loop

    # do all the good stuff...

    # Call systems
    reg.systemRegen()
    reg.systemPoison()
    reg.systemHealth()
    reg.systemCorpse()
    reg.update()

    limitExecution -= 1
    if limitExecution == 0: break

# #########################################
# Tests
# #########################################
when isMainModule and true:
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
        var h1 = getComponent(reg, e1, Health)
        h1.health = 20
        check reg.getComponent(e1, Health).health == 20
      check reg.hasComponent(e1, Health) == true
      reg.removeComponent(e1, Health)
      check reg.hasComponent(e1, Health) == false
    test "not there":
      doAssertRaises(ValueError):
        discard getComponent(reg, e1, Kaka)
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
          # echo "DESTRUCT MANA WAS:", comp.mana
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
      proc healthDestructor(reg: Registry, ent: Entity,  comp: Component) {.gcsafe.} =
        # echo cobj.ss # <- bound object
        cobj.cnt.inc
        # echo "In health destructor destructorInternalExplicitly:", $ent, " ", $(Health(comp).health)
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
      proc healthDestructor(reg: Registry, ent: Entity, comp: Component) {.gcsafe.} =
        # echo cobj.ss # <- bound object
        cobj.cnt.inc
        # echo "In health destructor destructorInternalImplicitly: ", $ent, " ", $(Health(comp).health)
      reg.addComponentDestructor(Health, healthDestructor)
      reg.destroyEntity(ee)
      reg.cleanup()
      check cobj.cnt == 1
    test "entitiesWithComp":
      reg = newRegistry()
      var ee1 = reg.newEntity()
      reg.addComponent(ee1, Health(health: 123))
      var ee2 = reg.newEntity()
      reg.addComponent(ee2, Health(health: 321))
      for (ent, compHealth) in reg.entitiesWithComp(Health):
        compHealth.health = compHealth.health * 2
      check reg.getComponent(ee1, Health).health == 246
      check reg.getComponent(ee2, Health).health == 642
    test "entities with comp overloads":
      reg = newRegistry()
      var ee1 = reg.newEntity()
      reg.addComponent(ee1, Health(health: 321))
      var ee2 = reg.newEntity()
      reg.addComponent(ee2, Health(health: 321))
      reg.addComponent(ee2, Mana(mana: 321))
      var idx = 0
      for (ent, compHealth, compMana) in reg.entitiesWithComp(Health, Mana):
        idx.inc
        compHealth.health = compHealth.health * 2
        compMana.mana = compMana.mana * 2
      check idx == 1
      check reg.getComponent(ee2, Health).health == 642
      check reg.getComponent(ee2, Mana).mana == 642
    test "entities with comp overloads 3 types":
      reg = newRegistry()
      var ee1 = reg.newEntity()
      reg.addComponent(ee1, Health(health: 321))
      reg.addComponent(ee1, Mana(mana: 321))
      reg.addComponent(ee1, Kaka(mana: 321))
      var idx = 0
      for (ent, compHealth, compMana, compKaka) in reg.entitiesWithComp(Health, Mana, Kaka):
        idx.inc
        compHealth.health = compHealth.health * 2
        compMana.mana = compMana.mana * 2
        compKaka.mana = compKaka.mana * 2
      check idx == 1
      check reg.getComponent(ee1, Health).health == 642
      check reg.getComponent(ee1, Mana).mana == 642
      check reg.getComponent(ee1, Kaka).mana == 642
    test "template version of api":
      reg = newRegistry()
      var ee1 = newEntity()
      addComponent(ee1, Health(health: 321))
      addComponent(ee1, Mana(mana: 642))
      ee1 := Kaka(mana: 642)
      for ee in entities(Health):
        check ee == 1
        check reg.getComponent(ee, Health).health == 321
        check getComponent(ee, Health).health == 321
        check ee[Health].health == 321
      for (ent, compHealth) in entitiesWithComp(Health):
        check ent == 1
        check compHealth.health == 321
      for (ent, compHealth, compMana) in entitiesWithComp(Health, Mana):
        check ent == 1
        check compHealth.health == 321
        check compMana.mana == 642
      for (ent, compHealth, compMana, compKaka) in entitiesWithComp(Health, Mana, Kaka):
        check ent == 1
        check compHealth.health == 321
        check compMana.mana == 642
        check compKaka.mana == 642


  suite "ecs->events":
    setup:
      var reg = newRegistry()
      type
        MyEvent = object
          hihi: string
          hoho: int
          ents: seq[int]
        SomeOtherEvent = object
          ents: seq[int]
      var obj = 0 #"From bound obj: asdads" # A bound obj
      proc cbMyEvent(ev: MyEvent)  =
        # echo "my event was triggered", ev.hihi, ev.hoho
        obj.inc
      proc cbMyEvent2(ev: MyEvent) =
        # echo "my event was triggered TWO", ev.hihi, ev.hoho
        obj.inc(2)
      proc cbSomeOtherEvent(ev: SomeOtherEvent) =
        echo "cbSomeOtherEvent", ev.ents
        obj.inc(3)
      proc cbSomeOtherEvent2(ev: SomeOtherEvent)  =
        echo "cbSomeOtherEvent2", ev.ents
        for ent in ev.ents:
          echo "ENT: ", ent
        obj.inc(4)
    test "simple events":
      reg.connect(MyEvent, cbMyEvent)
      reg.connect(MyEvent, cbMyEvent2)
      var myev = MyEvent()
      myev.hihi = "hihi"
      myev.hoho = 1337
      myev.ents = @[1,2,3]
      reg.trigger(myev)
      check obj == 3
    test "simple events disconnect":
      reg.connect(MyEvent, cbMyEvent)
      reg.connect(MyEvent, cbMyEvent2)
      var myev = MyEvent()
      reg.trigger(myev)
      check obj == 3
      reg.disconnect(MyEvent, cbMyEvent2)
      reg.trigger(myev)
      check obj == 4
    test "simple events disconnect all":
      reg.connect(MyEvent, cbMyEvent)
      reg.connect(MyEvent, cbMyEvent2)
      var myev = MyEvent()
      reg.trigger(myev)
      check obj == 3
      reg.disconnectAll(MyEvent)
      reg.trigger(myev)
      check obj == 3
    test "compile time type safety":
      check compiles(reg.connect(MyEvent, cbSomeOtherEvent)) == false
      check compiles(reg.connect(SomeOtherEvent, cbMyEvent2)) == false
    # test "triggerLater":
    #   reg.connect(MyEvent, cbMyEvent)
    #   var myev = MyEvent()
    #   reg.triggerLater(myev)
    #   check obj == 0




when isMainModule and false:

  import sequtils, sets
  iterator entitiesWithComp2[A, B](reg: Registry, aa: typedesc[A], bb: typedesc[B]): tuple[ent: Entity, a: A, b: B] =
    let h1 = ($aa).hash()
    let h2 = ($bb).hash()
    if reg.components.hasKey(h1) and reg.components.hasKey(h2):
      let hs1 = toHashSet[Entity](toSeq(reg.components[h1].keys()))
      let hs2 = toHashSet[Entity](toSeq(reg.components[h2].keys()))
      let res = hs1 * hs2
      for ent in res:
        yield (ent: ent, a: A reg.components[h1][ent], b: B reg.components[h2][ent])


  iterator entitiesWithCompSlow[A](reg: Registry, aa: typedesc[A]): tuple[ent: Entity, a: A] {.inline.} =
    # TODO SLOW! Remove!
    for ent in reg.entities(A):
        yield (ent: ent, a: reg.getComponent(ent, A))

  import benchy
  type
    Health = ref object of Component
      health: int
      maxHealth: int
    ManaObj = object of Component
      mana: int
      maxMana: int
    Mana = ref ManaObj
  var reg = newRegistry()
  for idx in 0..100_000:
    var ee1 = reg.newEntity()
    reg.addComponent(ee1, Health(health: 123))
    var ee2 = reg.newEntity()
    reg.addComponent(ee2, Health(health: 321))
    reg.addComponent(ee2, Mana(mana: 321))

  timeit "b1":
    var idx = 0
    for ent in reg.entities(Health):
      let compHealth = reg.getComponent(ent, Health)
      idx.inc
  timeit "b2":
    var idx = 0
    for ent, compHealth in reg.entitiesWithCompSlow(Health):
      idx.inc
  timeit "b3":
    var idx = 0
    for ent, compHealth in reg.entitiesWithComp(Health):
      idx.inc
  timeit "2 (old)":
    var idx = 0
    for ent, compHealth, compMana in reg.entitiesWithComp(Health, Mana):
      idx.inc
  timeit "2 (new with hashset)":
    var idx = 0
    for ent, compHealth, compMana in reg.entitiesWithComp2(Health, Mana):
      idx.inc

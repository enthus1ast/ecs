# ECS

A simple ECS with + basic signals.

For complete examples look into the `ecs.nim` file.

# Changelog:

- 0.3.0
  - Added template version of the api, that does not require `reg`

    For example:

    `reg.getComponent(e1, Health)`

    becomes:

    `getComponent(e1, Health)`

    or

    `e1[Health]`

  - added shortcuts for often used api:

    - `reg.addComponent(e1, Health(health: 10, maxHealth: 100))`
    - `reg.getComponent(e1, Health)`


    can now be written as:

    - `e1 := Health(health: 10, maxHealth: 100)`
    - `e1[Health]`





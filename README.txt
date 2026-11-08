RoadWeaver 26.3 initial-generation deadlock patch

Files in this archive mirror repository-relative paths. Copy/overwrite them into the root of your RoadWeaver project:

- common/src/main/java/net/shiroha233/roadweaver/generation/InitialGenManager.java
- fabric/src/main/java/net/shiroha233/roadweaver/planning/fabric/ServerPlanningHooks.java
- fabric/src/main/resources/roadweaver.mixins.json

What this changes:
- Removes the blocking Future.get()/awaitTermination startup path from InitialGenManager.
- Retains blockUntilDone as a deprecated non-blocking compatibility shim.
- Lets RoadGenerationService.tick() dispatch normal initial road work after the integrated server begins ticking.
- Updates initial-generation progress each server tick and runs the final snap/flush once the initial queue drains.
- Removes the MinecraftServer.prepareLevels mixin from roadweaver.mixins.json so setup happens from SERVER_STARTED instead.

Build on Windows with JDK 25:
  .\gradlew.bat clean build

This patch was created from the source currently visible in the GitHub repository. It has not been compiled or runtime-tested in this environment. Test on a NEW disposable world first; do not use your only copy of an existing save.

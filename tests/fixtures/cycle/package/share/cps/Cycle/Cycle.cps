{
  "name": "Cycle",
  "cps_version": "0.15.0",
  "cps_path": "@prefix@/share/cps/Cycle",
  "components": {
    "A": {"type": "interface", "requires": [":B"]},
    "B": {"type": "interface", "compile_requires": [":A"]}
  }
}

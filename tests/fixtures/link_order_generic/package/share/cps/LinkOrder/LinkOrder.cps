{
  "name": "LinkOrder",
  "cps_version": "0.15.0",
  "cps_path": "@prefix@/share/cps/LinkOrder",
  "default_components": ["R"],
  "components": {
    "R": {
      "type": "interface",
      "requires": [":A"],
      "link_requires": [":A"]
    },
    "A": {
      "type": "archive",
      "location": "@prefix@/lib/libA.a",
      "requires": [":B"]
    },
    "B": {
      "type": "archive",
      "location": "@prefix@/lib/libB.a"
    }
  }
}

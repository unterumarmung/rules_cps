{
  "name": "Bar",
  "cps_version": "0.15.0",
  "cps_path": "@prefix@/share/cps/Bar",
  "version": "2.0.0",
  "requires": {
    "Foo": {
      "version": "1.2.0",
      "components": ["static"],
      "hints": ["this-must-not-affect-resolution"]
    }
  },
  "default_components": ["bridge"],
  "components": {
    "bridge": {
      "type": "interface",
      "requires": ["Foo:static"]
    }
  }
}

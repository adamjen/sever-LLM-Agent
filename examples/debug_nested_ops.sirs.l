{
  "program": {
    "entry": "main",
    "functions": {
      "main": {
        "args": [],
        "return": "void",
        "body": [
          {
            "let": {
              "name": "baseline",
              "type": "f64",
              "value": {"literal": 2.0}
            }
          },
          {
            "let": {
              "name": "multiplier",
              "type": "f64",
              "value": {"literal": 3.0}
            }
          },
          {
            "let": {
              "name": "is_anomaly",
              "type": "f64",
              "value": {"literal": 1.0}
            }
          },
          {
            "let": {
              "name": "current_rate",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "mul",
                  "args": [
                    {"var": "baseline"},
                    {
                      "op": {
                        "kind": "add",
                        "args": [
                          {"literal": 1.0},
                          {
                            "op": {
                              "kind": "mul",
                              "args": [
                                {"var": "is_anomaly"},
                                {"var": "multiplier"}
                              ]
                            }
                          }
                        ]
                      }
                    }
                  ]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "current_rate"}]
              }
            }
          }
        ]
      }
    }
  }
}
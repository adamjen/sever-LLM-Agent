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
              "name": "normal_error_rate",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 2.0},
                    {"literal": 0.5}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "is_incident",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"literal": 0.05}]
                }
              }
            }
          },
          {
            "let": {
              "name": "spike_multiplier",
              "type": "f64",
              "value": {"literal": 10.0}
            }
          },
          {
            "let": {
              "name": "current_rate",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {"var": "normal_error_rate"},
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "is_incident"},
                          {"var": "spike_multiplier"}
                        ]
                      }
                    }
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "observed_errors",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "poisson",
                  "params": [{"var": "current_rate"}]
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "normal_error_rate"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "is_incident"}]
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
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "observed_errors"}]
              }
            }
          }
        ]
      }
    }
  }
}
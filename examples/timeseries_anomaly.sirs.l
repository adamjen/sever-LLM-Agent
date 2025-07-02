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
              "name": "historical_metrics",
              "value": {
                "array": [
                  {"literal": 2.0},
                  {"literal": 1.0},
                  {"literal": 3.0},
                  {"literal": 2.0},
                  {"literal": 1.0}
                ]
              }
            }
          },
          {
            "let": {
              "name": "baseline_rate",
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
              "name": "anomaly_detected",
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
              "name": "spike_factor",
              "type": "f64",
              "value": {"literal": 8.0}
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
                    {"var": "baseline_rate"},
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "anomaly_detected"},
                          {"var": "spike_factor"}
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
              "name": "current_errors",
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
            "let": {
              "name": "historical_sample",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "historical_metrics"},
                  "index": {"literal": 0}
                }
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "historical_sample"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "baseline_rate"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "anomaly_detected"}]
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
                "args": [{"var": "current_errors"}]
              }
            }
          }
        ]
      }
    }
  }
}
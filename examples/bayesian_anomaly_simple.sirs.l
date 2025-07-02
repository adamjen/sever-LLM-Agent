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
              "name": "anomaly_multiplier",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "lognormal",
                  "params": [
                    {"literal": 1.5},
                    {"literal": 0.5}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "is_anomaly_period",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"literal": 0.1}]
                }
              }
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
                    {"var": "baseline_rate"},
                    {
                      "op": {
                        "kind": "add",
                        "args": [
                          {"literal": 1.0},
                          {
                            "op": {
                              "kind": "mul",
                              "args": [
                                {"var": "is_anomaly_period"},
                                {"var": "anomaly_multiplier"}
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
            "let": {
              "name": "observed_errors_t1",
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
              "name": "observed_errors_t2",
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
              "name": "observed_errors_t3",
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
                "args": [{"var": "baseline_rate"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "is_anomaly_period"}]
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
                "args": [{"var": "observed_errors_t1"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "observed_errors_t2"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "observed_errors_t3"}]
              }
            }
          }
        ]
      }
    }
  }
}
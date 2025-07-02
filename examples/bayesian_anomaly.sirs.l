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
              "name": "changepoint_prob",
              "type": "f64",
              "value": {"literal": 0.1}
            }
          },
          {
            "let": {
              "name": "is_anomaly_period",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "changepoint_prob"}]
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
                "function": "print_anomaly_analysis",
                "args": [
                  {"var": "baseline_rate"},
                  {"var": "is_anomaly_period"},
                  {"var": "current_rate"},
                  {"var": "observed_errors_t1"},
                  {"var": "observed_errors_t2"},
                  {"var": "observed_errors_t3"}
                ]
              }
            }
          }
        ]
      },
      "print_anomaly_analysis": {
        "args": [
          {"name": "baseline", "type": "f64"},
          {"name": "is_anomaly", "type": "f64"},
          {"name": "current_rate", "type": "f64"},
          {"name": "errors_t1", "type": "f64"},
          {"name": "errors_t2", "type": "f64"},
          {"name": "errors_t3", "type": "f64"}
        ],
        "return": "void",
        "body": [
          {
            "expression": {
              "call": {
                "function": "print_string",
                "args": [{"literal": "=== Observability Anomaly Detection ==="}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "print_string",
                "args": [{"literal": "Baseline error rate: "}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "baseline"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "print_string",
                "args": [{"literal": "Anomaly detected: "}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "is_anomaly"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "print_string",
                "args": [{"literal": "Current rate: "}]
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
                "function": "print_string",
                "args": [{"literal": "Error counts: "}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "errors_t1"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "print_string",
                "args": [{"literal": ", "}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "errors_t2"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "print_string",
                "args": [{"literal": ", "}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "errors_t3"}]
              }
            }
          }
        ]
      },
      "print_string": {
        "args": [{"name": "text", "type": "str"}],
        "return": "void",
        "body": [
          {
            "expression": {
              "call": {
                "function": "std_print",
                "args": [{"var": "text"}]
              }
            }
          }
        ]
      }
    }
  }
}
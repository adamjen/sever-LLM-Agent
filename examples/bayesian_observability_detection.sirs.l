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
              "name": "observed_metrics",
              "value": {
                "array": [
                  {"literal": 2.0},
                  {"literal": 3.0},
                  {"literal": 1.0},
                  {"literal": 15.0},
                  {"literal": 12.0}
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
                    {"literal": 1.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "anomaly_threshold",
              "type": "f64",
              "value": {"literal": 10.0}
            }
          },
          {
            "let": {
              "name": "changepoint_prior",
              "type": "f64",
              "value": {"literal": 0.2}
            }
          },
          {
            "let": {
              "name": "time_point_1",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "observed_metrics"},
                  "index": {"literal": 0}
                }
              }
            }
          },
          {
            "let": {
              "name": "time_point_2",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "observed_metrics"},
                  "index": {"literal": 1}
                }
              }
            }
          },
          {
            "let": {
              "name": "time_point_3",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "observed_metrics"},
                  "index": {"literal": 2}
                }
              }
            }
          },
          {
            "let": {
              "name": "time_point_4",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "observed_metrics"},
                  "index": {"literal": 3}
                }
              }
            }
          },
          {
            "let": {
              "name": "time_point_5",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "observed_metrics"},
                  "index": {"literal": 4}
                }
              }
            }
          },
          {
            "let": {
              "name": "is_changepoint_t3",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "changepoint_prior"}]
                }
              }
            }
          },
          {
            "let": {
              "name": "is_changepoint_t4",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "changepoint_prior"}]
                }
              }
            }
          },
          {
            "let": {
              "name": "anomaly_rate",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 5.0},
                    {"literal": 2.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "rate_t4",
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
                          {"var": "is_changepoint_t4"},
                          {"var": "anomaly_rate"}
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
              "name": "predicted_t4",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "poisson",
                  "params": [{"var": "rate_t4"}]
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
                "args": [{"var": "is_changepoint_t4"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "time_point_4"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "predicted_t4"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "anomaly_rate"}]
              }
            }
          }
        ]
      }
    }
  }
}
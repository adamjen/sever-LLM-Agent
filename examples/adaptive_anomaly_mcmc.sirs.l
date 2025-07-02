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
              "name": "historical_error_data",
              "value": {
                "array": [
                  {"literal": 2.0},
                  {"literal": 1.0},
                  {"literal": 3.0},
                  {"literal": 2.0},
                  {"literal": 1.0},
                  {"literal": 15.0},
                  {"literal": 18.0},
                  {"literal": 2.0},
                  {"literal": 1.0},
                  {"literal": 3.0}
                ]
              }
            }
          },
          {
            "let": {
              "name": "learned_baseline_rate",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 3.0},
                    {"literal": 1.5}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "learned_anomaly_rate",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "gamma",
                  "params": [
                    {"literal": 8.0},
                    {"literal": 2.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "changepoint_probability",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "beta",
                  "params": [
                    {"literal": 1.0},
                    {"literal": 9.0}
                  ]
                }
              }
            }
          },
          {
            "let": {
              "name": "current_time_is_anomaly",
              "type": "f64",
              "value": {
                "sample": {
                  "distribution": "bernoulli",
                  "params": [{"var": "changepoint_probability"}]
                }
              }
            }
          },
          {
            "let": {
              "name": "current_expected_rate",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {
                            "op": {
                              "kind": "sub",
                              "args": [
                                {"literal": 1.0},
                                {"var": "current_time_is_anomaly"}
                              ]
                            }
                          },
                          {"var": "learned_baseline_rate"}
                        ]
                      }
                    },
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "current_time_is_anomaly"},
                          {"var": "learned_anomaly_rate"}
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
              "name": "recent_observation",
              "type": "f64",
              "value": {
                "index": {
                  "array": {"var": "historical_error_data"},
                  "index": {"literal": 9}
                }
              }
            }
          },
          {
            "let": {
              "name": "confidence_score",
              "type": "f64",
              "value": {
                "op": {
                  "kind": "add",
                  "args": [
                    {"var": "changepoint_probability"},
                    {
                      "op": {
                        "kind": "mul",
                        "args": [
                          {"var": "current_time_is_anomaly"},
                          {"var": "current_expected_rate"}
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
                "args": [{"var": "learned_baseline_rate"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "learned_anomaly_rate"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "current_time_is_anomaly"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "recent_observation"}]
              }
            }
          },
          {
            "expression": {
              "call": {
                "function": "std_print_float",
                "args": [{"var": "confidence_score"}]
              }
            }
          }
        ]
      }
    }
  }
}
import json
import joblib
import numpy as np
import pandas as pd
from datetime import date
# from azureml.core.model import Model


# Called when a request is received
def run(raw_data):
    # pass raw_data as string
    global data
    data = pd.DataFrame(raw_data)
#     data = data[(data['PreviousLoanAmt'].isnull() == False) & (data['PreviousLoanAmt'] != 0) & (data['LastPaymentDate'].isnull() == False)
#                   & (data['Pay_Previous'].isnull() == False) & (data['YearsWithUs'] >= 0) & (data['Salary'].isnull() == False) & (data['Salary'] >= 1000) & (data['Age'] >= 18)
#                 & (data['Profit_Historical'] > 0) & (data['Profit_Previous'] > 0)]    
    #(data['Salary'].isnull() == False) & (data['Bankaccountlengthmonths'].isnull() == False) & (data['Monthsatresidence'].isnull() == False) & (data['EmploymentLength'].isnull() == False)
                  
#    load the modeln
#     model = joblib.load('C:/Users/brigh/OneDrive - The Strategic Group/MPD-MFC/Risk-based Pricing/xgb_renewal_model.pkl')
    model = joblib.load('C:/Users/brigh/OneDrive - The Strategic Group/Model Deployment/MPD renewal model v1.1 deployment files/xgb_renewal_model.pkl')
    data_fitting = pre_processing(data)
    predictions = model.predict(data_fitting)
    prob = model.predict_proba(data_fitting)
    score = prob[:,0]*1000
#     # Return the predictions as any JSON serializable format
    data['Score'] = score
    return data


def pre_processing(data):
    # clean Salary
    list_i = []
    list_j = []
    for i in data['Salary']:
    #     print(i, type(i))
        if type(i) == str:
            if i[0] == '$':
                i = i[1:]
            if i[1] == '.' and i[-3] == '.':
                i = i[0] + i[2:]
        list_i.append(i)

    for j in data['EmploymentLength']:
        if type(j) == str:
            if 'N' in j or '/' in j or 'o' in j or 'NULL' in j or j == '':
                j = 0
        list_j.append(j)
    data['Salary'] = list_i
    data['EmploymentLength'] = list_j
    data['PreviousLoanAmt'] = data['PreviousLoanAmt'].astype(float)
    data['Bankaccountlengthmonths'] = data['Bankaccountlengthmonths'].astype(float)
    data['Monthsatresidence'] = data['Monthsatresidence'].astype(float)
    data['EmploymentLength'] = data['EmploymentLength'].astype(float)
    data['EmploymentLength'].fillna(3, inplace = True)
    data['Bankaccountlengthmonths'].fillna(30, inplace = True)
    data['Monthsatresidence'].fillna(36, inplace = True)
    data['StaticPool_Historical'] = data['Pay_Historical']/data['HistoricalLoanAmt']
    data['StaticPool_Previous'] = data['Pay_Previous']/data['PreviousLoanAmt']
    train_vars = ['StaticPool_Historical', 'StaticPool_Previous', 'Age', 'YearsWithUs', 'NumberOfLoansBefore', 'Non-Active Duration',  'PreviousLoanAmt', 'HistoricalLoanAmt',  'Bankaccountlengthmonths', 'Monthsatresidence', 'EmploymentLength', 'WOEntries_Historical']
    data = data[train_vars]
    return data


run(raw_data)
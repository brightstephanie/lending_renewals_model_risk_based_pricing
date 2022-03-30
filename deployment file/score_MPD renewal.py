import json
import joblib
import numpy as np
import pandas as pd
from azureml.core.model import Model

# Called when the service is loaded
def init():
    global model
    # Get the path to the registered model file and load it
    model_path = Model.get_model_path('xgb_renewal_model')
    model = joblib.load(model_path)

# Called when a request is received
def run(raw_data):
    # pass raw_data as string
    global data
    data = json.loads(raw_data)
    data = pd.DataFrame(data)
    data = pre_processing(data)
    predictions = model.predict(data)
    prob = model.predict_proba(data)
    score = prob[:,0]*1000
    # Return the predictions as any JSON serializable format
    return prob.tolist(), score.tolist()

def pre_processing(data):
    # clean Salary
    list_i = []
    list_j = []
    for i in data['Salary']:
        #print(i, type(i))
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
    #data['StaticPool_Historical'] = data['Pay_Historical']/data['HistoricalLoanAmt']
    #data['StaticPool_Previous'] = data['Pay_Previous']/data['PreviousLoanAmt']
    train_vars = ['StaticPool_Historical', 'StaticPool_Previous', 'Age', 'YearsWithUs', 
                  'NumberOfLoansBefore', 'Non-Active Duration',  'PreviousLoanAmt', 
                  'HistoricalLoanAmt',  'Bankaccountlengthmonths', 'Monthsatresidence', 
                  'EmploymentLength', 'WOEntries_Historical']
    data = data[train_vars]
    return data
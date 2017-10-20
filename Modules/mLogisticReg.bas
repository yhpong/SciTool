Attribute VB_Name = "mLogisticReg"
Option Explicit

'========================================================
'Perform binary logistic regression with gradient descent
'========================================================
'Output: beta(1:D+1), regression coefficients of D-dimension, the D+1 element is the bias term
'Input: y(1:N), binary target N observations
'       x(1:N,1:D), D-dimensional feature vector of N observations
'       learn_rate, learning rate for gradient descent
Sub Binary_Train(beta() As Double, y As Variant, x As Variant, _
        Optional learn_rate As Double = 0.001, Optional momentum As Double = 0.5, _
        Optional mini_batch As Long = 5, _
        Optional epoch_max As Long = 1000, _
        Optional conv_max As Long = 5, Optional conv_tol As Double = 0.000001, _
        Optional loss_function As Variant, _
        Optional L1 As Double = 0, Optional L2 As Double = 0, _
        Optional adaptive_learn As Boolean = True, _
        Optional show_progress As Boolean = True)
Dim i As Long, j As Long, k As Long, m As Long, n As Long, n_dimension As Long, ii As Long
Dim batch_count As Long, epoch As Long, conv_count As Long
Dim tmp_x As Double, tmp_y As Double, delta As Double, y_output As Double
Dim max_gain As Double
Dim loss() As Double, grad() As Double, grad_prev() As Double, gain() As Double, beta_chg() As Double
Dim iArr() As Long
    n = UBound(x, 1)            'number of observations
    n_dimension = UBound(x, 2)  'number of dimensions
    max_gain = 1 / learn_rate   's.t. max learn rate is 1
    
    'Initialize beta() to zeroes
    ReDim beta(1 To n_dimension + 1)
    ReDim beta_chg(1 To n_dimension + 1)

    'Perform gradient descent
    conv_count = 0
    ReDim loss(1 To epoch_max)
    For epoch = 1 To epoch_max
        
        If show_progress = True Then
            If epoch Mod 100 = 0 Then
                DoEvents
                Application.StatusBar = "mLogisticReg: Binary_Train: " & epoch & "/" & epoch_max
            End If
        End If
        
        'Shuffle data set
        iArr = modMath.index_array(1, n)
        Call modMath.Shuffle(iArr)
        
        'Reset gradients
        batch_count = 0
        ReDim grad(1 To n_dimension + 1)
        ReDim grad_prev(1 To n_dimension + 1)
        ReDim gain(1 To n_dimension + 1)
        For j = 1 To n_dimension + 1
            gain(j) = 1
        Next j
        
        'Scan through dataset
        For ii = 1 To n
            i = iArr(ii)
            
            'beta dot x
            y_output = beta(n_dimension + 1)
            For j = 1 To n_dimension
                y_output = y_output + beta(j) * x(i, j)
            Next j
            y_output = 1# / (1 + Exp(-y_output)) 'Sigmoid function
            'loss(epoch) = loss(epoch) - y(i) * Log(y_output) _
                    -(1 - y(i)) * Log(1 - y_output) 'accumulate loss function
            
            'accumulate gradient
            delta = y_output - y(i)
            For j = 1 To n_dimension
                grad(j) = grad(j) + x(i, j) * delta
            Next j
            grad(n_dimension + 1) = grad(n_dimension + 1) + delta
            
            'update beta() when mini batch count is reached
            batch_count = batch_count + 1
            If batch_count = mini_batch Or ii = n Then
                For j = 1 To n_dimension + 1
                    grad(j) = grad(j) / batch_count
                Next j
                If L1 > 0 Then 'L1-regularization
                    For j = 1 To n_dimension
                        grad(j) = grad(j) + L1 * Sgn(beta(j))
                    Next j
                End If
                If L2 > 0 Then 'L2-regularization
                    For j = 1 To n_dimension
                        grad(j) = grad(j) + L2 * beta(j)
                    Next j
                End If
                
                If adaptive_learn = True Then
                    Call calc_gain(grad, grad_prev, gain, max_gain)
                End If
                
                For j = 1 To n_dimension + 1
                    beta_chg(j) = momentum * beta_chg(j) - grad(j) * learn_rate * gain(j)
                    beta(j) = beta(j) + beta_chg(j)
                Next j
                
                'reset mini batch count and gradient
                batch_count = 0
                grad_prev = grad
                ReDim grad(1 To n_dimension + 1)
            End If
            
        Next ii

        'loss(epoch) = loss(epoch) / n
        loss(epoch) = Cross_Entropy(y, Binary_InOut(beta, x))
        
        'early terminate on convergence
        If epoch > 1 Then
            If loss(epoch) < 0.05 Then
                ReDim Preserve loss(1 To epoch)
                Exit For
            End If
            If loss(epoch) <= loss(epoch - 1) Then
                conv_count = conv_count + 1
                If conv_count > conv_max Then
                    If (loss(epoch - 1) - loss(epoch)) < conv_tol Then
                        ReDim Preserve loss(1 To epoch)
                        Exit For
                    End If
                End If
            Else
                conv_count = 0
            End If
        End If
        
    Next epoch
    
    If IsMissing(loss_function) = False Then loss_function = loss
    Erase loss, grad, grad_prev, gain, beta_chg, iArr
    Application.StatusBar = False
End Sub


'========================================================
'Perform K-fold crossvalidation to find optimal L1 & L2 regularization
'========================================================
Sub Binary_Train_CV(beta() As Double, y As Variant, x As Variant, Optional k_fold As Long = 10, _
        Optional learn_rate As Double = 0.001, Optional momentum As Double = 0.5, _
        Optional mini_batch As Long = 5, _
        Optional epoch_max As Long = 1000, _
        Optional conv_max As Long = 5, Optional conv_tol As Double = 0.000001, _
        Optional loss_function As Variant, _
        Optional L1_max As Double = 0.01, Optional L2_max As Double = 2, _
        Optional adaptive_learn As Boolean = True)
Dim i As Long, j As Long, k As Long, m As Long, n As Long, n_dimension As Long
Dim i_cv As Long, ii As Long, jj As Long, ii_max As Long, jj_max As Long
Dim n_train As Long, n_validate As Long
Dim tmp_x As Double, L1 As Double, L2 As Double
Dim loss() As Double, loss_min As Double
Dim accur() As Double, accur_max As Double
Dim y_output() As Double
Dim iArr() As Long, i_validate() As Long, i_train() As Long
Dim x_train() As Double, x_validate() As Double
Dim y_train() As Double, y_validate() As Double
    n = UBound(x, 1)            'number of observations
    n_dimension = UBound(x, 2)  'number of dimensions
    n_validate = n \ k_fold
    n_train = n - n_validate
    
    'Shuffle data set
    iArr = modMath.index_array(1, n)
    Call modMath.Shuffle(iArr)
    
    ii_max = 0: jj_max = 0
    L1 = 0: L2 = 0
    If L1_max > 0 Then ii_max = 5
    If L2_max > 0 Then jj_max = 5
    
    'ReDim accur(0 To ii_max, 0 To jj_max)
    ReDim loss(0 To ii_max, 0 To jj_max)
    
    'Outer loop for different L1 & L2 values
    For ii = 0 To ii_max
        If ii_max > 0 Then L1 = ii * L1_max / ii_max
        For jj = 0 To jj_max
            If jj_max > 0 Then L2 = jj * L2_max / jj_max
            
            'K-fold cross-validation
            For i_cv = 1 To k_fold
            
                DoEvents
                Application.StatusBar = "Binary_Train_CV: " & ii & "/" & ii_max & _
                        " ; " & jj & "/" & jj_max & ";" & i_cv & "/" & k_fold
                        
                Call modMath.CrossValidate_set(i_cv, k_fold, iArr, i_validate, i_train)
                Call modMath.Filter_Array(y, y_validate, i_validate)
                Call modMath.Filter_Array(x, x_validate, i_validate)
                Call modMath.Filter_Array(y, y_train, i_train)
                Call modMath.Filter_Array(x, x_train, i_train)
                
                Call Binary_Train(beta, y_train, x_train, learn_rate, momentum, _
                    mini_batch, epoch_max, conv_max, conv_tol, , L1, L2, adaptive_learn, False)
                    
                y_output = Binary_InOut(beta, x_validate)
                'accur(ii, jj) = accur(ii, jj) + Accuracy(y_validate, y_output) * UBound(y_validate) / n
                loss(ii, jj) = loss(ii, jj) + Cross_Entropy(y_validate, y_output) / k_fold
                
            Next i_cv
        Next jj
    Next ii
    
    'Find L1 & L2 that gives lowest loss
    loss_min = Exp(70)
    For ii = 0 To ii_max
        For jj = 0 To jj_max
            If loss(ii, jj) < loss_min Then
                loss_min = loss(ii, jj)
                If ii_max > 0 Then L1 = ii * L1_max / ii_max
                If jj_max > 0 Then L2 = jj * L2_max / jj_max
            End If
        Next jj
    Next ii
    Debug.Print "Binary_Train_CV: Best(L1,L2)= (" & L1 & ", " & L2; "), loss=" & loss_min
    
'    accur_max = -Exp(70)
'    For ii = 0 To 5
'        For jj = 0 To 5
'            If accur(ii, jj) > accur_max Then
'                accur_max = accur(ii, jj)
'                L1 = ii * L1_max / 5
'                L2 = jj * L2_max / 5
'            End If
'        Next jj
'    Next ii
'    Debug.Print "Binary_Train_CV: Best(L1,L2)= (" & L1 & ", " & L2; "), accuracy=" & Format(accur_max, "0.0%")
    
    'Use selected L1 & L2 to train on whole data set
    Call Binary_Train(beta, y, x, learn_rate, momentum, _
            mini_batch, epoch_max, conv_max, conv_tol, loss, L1, L2, adaptive_learn, True)
            
    If IsMissing(loss_function) = False Then loss_function = loss

    Erase x_train, x_validate, y_train, y_validate
    Erase iArr, i_validate, i_train
    Erase loss, accur, y_output
    Application.StatusBar = False
End Sub


'Calculate accuracy
Function Accuracy(y_tgt As Variant, y As Variant) As Double
Dim i As Long, n As Long
Dim tmp_x As Double
    n = UBound(y, 1)
    tmp_x = 0
    For i = 1 To n
        If y_tgt(i) >= 0.5 Then
            If y(i) >= 0.5 Then tmp_x = tmp_x + 1
        ElseIf y_tgt(i) < 0.5 Then
            If y(i) < 0.5 Then tmp_x = tmp_x + 1
        End If
    Next i
    Accuracy = tmp_x / n
End Function


'Calculate cross entropy
Function Cross_Entropy(y_tgt As Variant, y As Variant) As Double
Dim i As Long, n As Long
Dim tmp_x As Double
    n = UBound(y, 1)
    tmp_x = 0
    For i = 1 To n
        tmp_x = tmp_x - y_tgt(i) * Log(y(i)) - (1 - y_tgt(i)) * Log(1 - y(i))
    Next i
    Cross_Entropy = tmp_x / n
End Function


'===========================
'Output from logistic model
'===========================
'Output: y(1:N), binary classification output
'Input:  beta(1:D+1), regression coefficients of D-dimension, the D+1 element is the bias term
'        x(1:N,1:D), D-dimensional feature vector of N observations
'        force_binary, if set to true then y() will be rounded to exactly 0 or 1.
Function Binary_InOut(beta() As Double, x As Variant, Optional force_binary As Boolean = False) As Double()
Dim i As Long, j As Long, k As Long, n As Long, n_dimension As Long
Dim tmp_x As Double
Dim y() As Double
    n = UBound(x, 1)
    n_dimension = UBound(x, 2)
    ReDim y(1 To n)
    For i = 1 To n
        tmp_x = beta(n_dimension + 1)
        For j = 1 To n_dimension
            tmp_x = tmp_x + beta(j) * x(i, j)
        Next j
        y(i) = 1# / (1 + Exp(-tmp_x))
    Next i
    If force_binary = True Then
        For i = 1 To n
            If y(i) >= 0.5 Then
                y(i) = 1
            Else
                y(i) = 0
            End If
        Next i
    End If
    Binary_InOut = y
    Erase y
End Function


Sub Rescale_beta(beta() As Double, x_mean() As Double, x_sd() As Double)
Dim i As Long, n As Long
    n = UBound(beta) - 1
    For i = 1 To n
        beta(n + 1) = beta(n + 1) - beta(i) * x_mean(i) / x_sd(i)
        beta(i) = beta(i) / x_sd(i)
    Next i
End Sub


Private Sub calc_gain(grad() As Double, grad_prev() As Double, gain() As Double, max_gain As Double)
Dim i As Long, n As Long
    n = UBound(grad)
    For i = 1 To n
        If Sgn(grad(i)) = Sgn(grad_prev(i)) Then
            gain(i) = gain(i) * 1.1
        Else
            gain(i) = gain(i) * 0.9
        End If
        If gain(i) > max_gain Then gain(i) = max_gain
        If gain(i) < 0.01 Then gain(i) = 0.01
    Next i
End Sub

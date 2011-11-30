fragSrc=''
vertSrc=''
mvMatrix=mat4.create()
pMatrix=mat4.create()
modelVertexBuffer=null
shaderProgram=null
angle=0

setMatrixUniforms=(gl)->
    gl.uniformMatrix4fv(shaderProgram.pMatrixUniform, false, pMatrix)
    gl.uniformMatrix4fv(shaderProgram.mvMatrixUniform, false, mvMatrix)

getShader=(gl,name)->
    if name=='shader-fs'
        fs=gl.createShader gl.FRAGMENT_SHADER
        gl.shaderSource fs,fragSrc
        gl.compileShader fs
        if not gl.getShaderParameter fs,gl.COMPILE_STATUS
            console.log 'FS log',gl.getShaderInfoLog fs
        fs
        
    else if name=='shader-vs'
        vs=gl.createShader gl.VERTEX_SHADER
        gl.shaderSource vs, vertSrc
        gl.compileShader vs
        if not gl.getShaderParameter vs,gl.COMPILE_STATUS
            console.log 'VS log',gl.getShaderInfoLog vs
        
        vs
    else
        throw Exception('shader not found')

initShader=(gl)->
    fs=getShader gl,'shader-fs'
    vs=getShader gl,'shader-vs'
    
    prog=gl.createProgram()
    gl.attachShader prog, vs
    gl.attachShader prog, fs
    gl.linkProgram prog
    
    if not gl.getProgramParameter prog, gl.LINK_STATUS
        console.log 'shader initilization failed'
    else
        gl.useProgram prog
        shaderProgram=prog
        shaderProgram.vertexPositionAttribute = gl.getAttribLocation(shaderProgram, "aVertexPosition")
        gl.enableVertexAttribArray(shaderProgram.vertexPositionAttribute)

        shaderProgram.pMatrixUniform = gl.getUniformLocation(shaderProgram, "uPMatrix")
        shaderProgram.mvMatrixUniform = gl.getUniformLocation(shaderProgram, "uMVMatrix")

initBuffer=(gl)->
    modelVertexBuffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, modelVertexBuffer)
    vertices = [
         0.0,  1.0,  0.0,
        -1.0, -1.0,  0.0,
         1.0, -1.0,  0.0
    ]
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(vertices), gl.STATIC_DRAW)
    modelVertexBuffer.itemSize = 3
    modelVertexBuffer.numItems = 3


drawScene=(gl)->
    gl.viewport(0, 0, gl.viewportWidth, gl.viewportHeight)
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

    mat4.perspective(45, gl.viewportWidth / gl.viewportHeight, 0.1, 100.0, pMatrix)

    mat4.identity(mvMatrix)

    mat4.translate(mvMatrix, [-1.5, 0.0, -15.0])
    mat4.rotate(mvMatrix, angle,[0,1,0])
    mat4.scale(mvMatrix,[0.1,0.1,0.1])
    gl.bindBuffer(gl.ARRAY_BUFFER, modelVertexBuffer)
    gl.vertexAttribPointer(shaderProgram.vertexPositionAttribute, modelVertexBuffer.itemSize, gl.FLOAT, false, 0, 0)
    setMatrixUniforms(gl)
    gl.drawArrays(gl.TRIANGLES, 0, modelVertexBuffer.numItems)


$.ajax
    async: false
    url: $('script[type="text/gl-fragment"]').attr 'src' 
    success: (d)-> fragSrc=d

$.ajax
    async: false
    url: $('script[type="text/gl-vertex"]').attr 'src'
    success: (d) -> vertSrc=d


render_layer=(ctx,layer)->

    ctx.save()
    #ctx.scale 0.5, 0.5
    
    # draw image
    for iy in [0...layer.ny]
        for ix in [0...layer.nx]
            if layer.array[ix+iy*layer.nx]>0
                ctx.fillStyle='white'
            else
                ctx.fillStyle='black'

            ctx.fillRect ix,iy,1,1
    
    ctx.restore()
    

draw_gcode=(ctx,cmd,model,offset)->
    prev=null
    
    ctx.fillStyle='white'
    ctx.fillRect 0,0,500,500
    

    
    margin_px=10
    margin_mm=5
    k=Math.min(
       (500-margin_px*2)/(margin_mm*2+model.pos1[0]-model.pos0[0]),
       (500-margin_px*2)/(margin_mm*2+model.pos1[1]-model.pos0[1]))
    xm=(model.pos1[0]+model.pos0[0])/2+offset[0]
    ym=(model.pos1[1]+model.pos0[1])/2+offset[1]
    console.log model.pos0,k,xm,ym
    
    ctx.save()   
    ctx.translate 250,250
    ctx.scale k,k
    ctx.translate -xm,-ym
    ctx.lineWidth=1/k
    ctx.strokeStyle='black'
    
    track=(cmd)->
        switch cmd.type
            when 'command'
                if cmd.arguments.v?
                    switch cmd.code
                        when 'G0' # fast move
                            ctx.lineWidth=1/k
                            ctx.strokeStyle='rgba(0,0,255,0.5)'
                        when 'G1' # extrude move
                            ctx.lineWidth=3/k
                            ctx.strokeStyle='rgba(0,0,0,0.5)'
                        else
                            ctx.lineWidth=1/k
                            ctx.strokeStyle='rgba(255,0,0,0.5)'
                    
                    if prev==null
                        ctx.beginPath()
                        ctx.arc cmd.arguments.v.elements[0], cmd.arguments.v.elements[1], 5/k, 0, 2*Math.PI
                        ctx.closePath()
                        ctx.stroke()
                    else
                        ctx.beginPath()
                        ctx.moveTo prev.elements[0], prev.elements[1]
                        ctx.lineTo cmd.arguments.v.elements[0], cmd.arguments.v.elements[1]
                        ctx.closePath()
                        ctx.stroke()
                    prev=cmd.arguments.v
                else
                    switch cmd.code
                        when 'G4' # dwell
                            ctx.fillStyle='rgba(0,255,0,0.5)'
                        else
                            ctx.fillStyle='rgba(255,0,0,0.5)'
                    
                    if prev!=null
                        ctx.beginPath()
                        ctx.arc prev.elements[0], prev.elements[1], 3/k, 0, 2*Math.PI
                        ctx.closePath()
                        ctx.stroke()
                    
            when 'block'
                for cc in cmd.sequence
                    track cc
    
    track cmd
    ctx.restore()

# densely pack triangles into float array
pack_vbuffer=(tris)->
    vbuf=new Float32Array(9*tris.length)
    
    ofs=0
    for tri in tris
        vbuf.set tri[0], ofs
        vbuf.set tri[1], ofs+3
        vbuf.set tri[2], ofs+6
        ofs+=9
    
    vbuf


# if e_base is specified, replace ER with accumulated E value
render_command=(cmd,e_base)->
    format=(n,v)->
        if n=='v'
            ls='XYZ'
            i=0
            
            for e in v.elements
                "#{ls[i++]}#{e.toFixed 2}"
        else if n=='x' or n=='y' or n=='z' or n=='e'
            ["#{n.toUpperCase()}#{v.toFixed 2}"]
        else if n=='f' or n=='p'
            ["#{n.toUpperCase()}#{Math.floor v}"]
        else if n=='er'
            if e_base!=null
                e_base+=v
                ["E#{e_base.toFixed 2}"]
            else
                ["ER#{v.toFixed 2}"]
        else
            []
    
    expand=(cmd)->
        if cmd.type=='comment'
            ["; #{cmd.message}"]
        else if cmd.type=='command'
            words=[cmd.code]
            for n,v of cmd.arguments
                words=words.concat format n,v
            [words.join ' ']
        else if cmd.type=='block'
            ls=["; #{cmd.label}"]
            for cc in cmd.sequence
                ls=ls.concat expand cc
            ls
        else
            ["; unknown command #{cmd}"]
    
    expand cmd


gcode_to_jstree=(cmd)->
    switch cmd.type
        when 'command'
            data: (render_command cmd,null).join ' / '
            metadata: cmd
        when 'block'
            data: cmd.label
            metadata: cmd
            children: (gcode_to_jstree cc for cc in cmd.sequence)
        when 'comment'
            data: cmd.message
            metadata: cmd


$ ->
    # setup widgets
    $('#menu').tabs()
    $('#prog_model').progressbar {value:0}
    $('#prog_conv').progressbar {value:0}
                    
    # setup 2d view
    ctx=$('#view_2d')[0].getContext '2d'
    ctx_gcode =$('#view_gcode')[0].getContext '2d'
    
    # setup 3d view
    cv=$('#view_3d')[0]
    
    gl=cv.getContext('experimental-webgl')
    if gl!=null
        gl.viewportWidth=cv.width
        gl.viewportHeight=cv.height
        try
            initShader(gl)
            initBuffer(gl)
            
            gl.clearColor(1.0, 1.0, 1.0, 1.0)
            gl.enable(gl.DEPTH_TEST)
            drawScene(gl)
        catch err
            console.log err
            $('#view').append "WebGL error: #{err}"
            gl=null
    else
        $('#view').append 'WebGL is unavailable in this browser'
    
    model=null
    
    
    $('#btn_finish_conv').click ->
        offset=(parseFloat $("#offset_#{axis}").val() for axis in ['x','y','z'])
        lth=parseFloat $('#layer_thickness').val()
        hs=parseFloat $('#head_speed').val()
        s_coeff=parseFloat $('#section_coeff').val()
        lwidth=parseFloat $('#ext_width').val()
        raft=$('#raft').attr('checked')
        
        w=new Worker 'generate.js'
        w.onerror=(ev)->
            console.log 'generator worker emitted error:',ev
        
        w.onmessage=(ev)->
            switch ev.data.type
                when 'debug'
                    console.log.apply console, ev.data.message
                when 'layer'
                    render_layer ctx, ev.data.layer
                when 'tick'
                    $('#prog_conv').progressbar 'value', 100*ev.data.progress
                when 'finish'
                    console.log ev.data
                    w.terminate()
                    model.gcode=ev.data.gcode
                    
                    $('#gcode_tree').jstree
                        json_data:
                            data: gcode_to_jstree model.gcode
                        themes:
                            theme: 'apple'
                            icons: false                
                        plugins: ['json_data','themes','ui']
                    
                    $('#gcode_tree').bind 'select_node.jstree', (ev,data)->
                        draw_gcode ctx_gcode, data.rslt.obj.data(), model,
                            (parseFloat $("#offset_#{axis}").val() for axis in ['x','y'])
                    
                    $('#prog_conv').progressbar 'value', 100

            
        $('#commands').text ''
        w.postMessage
            raft: raft
            section_coeff: s_coeff
            lwidth: lwidth
            speed: hs
            offset: offset
            layer_thickness: lth
            model: model
    
    $('#btn_finish_prev').click ->
        data=(render_command model.gcode, 0).join '\n'
        window.location="data:data:text/plain;base64,#{btoa data}"
    
    
    on_model_load=(tris)->
        $('#prog_model').progressbar 'value', 100
        
        console.log 'calculating bounding box'
        xmin=1e10
        xmax=-1e10
        ymin=1e10
        ymax=-1e10
        zmin=1e10
        zmax=-1e10
        for tri in tris
            for v in tri
                xmin=Math.min(v[0],xmin)
                xmax=Math.max(v[0],xmax)
                ymin=Math.min(v[1],ymin)
                ymax=Math.max(v[1],ymax)
                zmin=Math.min(v[2],zmin)
                zmax=Math.max(v[2],zmax)
        
        console.log 'x: from ',xmin,' to ',xmax
        console.log 'y: from ',ymin,' to ',ymax
        console.log 'z: from ',zmin,' to ',zmax
        
        # pure JSON representation of model
        model=
            tris: tris
            pos0: [xmin,ymin,zmin]
            pos1: [xmax,ymax,zmax]
        
        # configure layer pos slider and attach handler
        thickness=parseFloat $('#layer_th').val()
        $('#layer_pos').attr 'min', zmin
        $('#layer_pos').attr 'max', zmax
        
        # show size in tab_trans
        pos0=$V(model.pos0)
        pos1=$V(model.pos1)
        diag=pos1.subtract pos0
        for i in [1..3]
            $("tbody tr:nth-child(#{i}) td:nth-child(2)").text pos0.e(i).toFixed 2
            $("tbody tr:nth-child(#{i}) td:nth-child(3)").text pos1.e(i).toFixed 2
            $("tbody tr:nth-child(#{i}) td:nth-child(4)").text diag.e(i).toFixed 2
        
        if gl!=null
            console.log 'STL loaded on main memory. transferring to GPU'
            vbuf=pack_vbuffer tris
            
            gl.bindBuffer(gl.ARRAY_BUFFER, modelVertexBuffer)
            gl.bufferData(gl.ARRAY_BUFFER, vbuf, gl.STATIC_DRAW)
            modelVertexBuffer.itemSize = 3
            modelVertexBuffer.numItems = tris.length*3
        
            redraw=()->
                angle+=0.02
                drawScene(gl)
                setTimeout redraw,50
            redraw()
    
    $('input[type=file]').change (ev)->
        load_stl ev.target.files[0],on_model_load, (err)->console.log err
        
        
        

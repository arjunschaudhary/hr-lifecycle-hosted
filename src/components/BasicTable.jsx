export default function BasicTable({
columns,
data
}){


return (

<div className="table-container">


<table>

<thead>

<tr>

{
columns.map(col=>

<th key={col.key}>
{col.label}
</th>

)

}

</tr>

</thead>



<tbody>


{
data.length ?

data.map((row,index)=>(

<tr key={index}>

{
columns.map(col=>

<td key={col.key}>

{
col.render
?
col.render(row)
:
row[col.key]
}

</td>

)

}

</tr>


))

:

<tr>

<td colSpan={columns.length}>

No data available

</td>

</tr>

}



</tbody>


</table>


</div>

)

}